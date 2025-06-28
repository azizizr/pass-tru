
-- Create enum for API key status
CREATE TYPE api_key_status AS ENUM ('active', 'suspended', 'revoked');

-- Create API keys table
CREATE TABLE public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  key_prefix TEXT NOT NULL,
  permissions JSONB DEFAULT '{}',
  rate_limit_per_hour INTEGER DEFAULT 1000,
  status api_key_status DEFAULT 'active',
  last_used_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create API usage logs table
CREATE TABLE public.api_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  api_key_id UUID REFERENCES public.api_keys(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  response_status INTEGER,
  response_time_ms INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create webhooks table
CREATE TABLE public.webhooks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  secret TEXT NOT NULL,
  events TEXT[] NOT NULL,
  is_active BOOLEAN DEFAULT true,
  retry_count INTEGER DEFAULT 3,
  timeout_seconds INTEGER DEFAULT 30,
  last_triggered_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create webhook delivery logs table
CREATE TABLE public.webhook_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id UUID REFERENCES public.webhooks(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL,
  response_status INTEGER,
  response_body TEXT,
  delivery_attempts INTEGER DEFAULT 1,
  delivered_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on all tables
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

-- RLS Policies for API keys
CREATE POLICY "Super admins can manage all API keys" ON public.api_keys
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can manage their own API keys" ON public.api_keys
  FOR ALL USING (auth.uid() = client_id);

-- RLS Policies for API usage logs
CREATE POLICY "Super admins can view all API usage" ON public.api_usage_logs
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Clients can view their API usage" ON public.api_usage_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.api_keys ak 
      WHERE ak.id = api_key_id AND ak.client_id = auth.uid()
    )
  );

-- RLS Policies for webhooks
CREATE POLICY "Super admins can manage all webhooks" ON public.webhooks
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can manage their own webhooks" ON public.webhooks
  FOR ALL USING (auth.uid() = client_id);

-- RLS Policies for webhook deliveries
CREATE POLICY "Super admins can view all webhook deliveries" ON public.webhook_deliveries
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Clients can view their webhook deliveries" ON public.webhook_deliveries
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.webhooks w 
      WHERE w.id = webhook_id AND w.client_id = auth.uid()
    )
  );

-- Function to generate API key
CREATE OR REPLACE FUNCTION public.generate_api_key()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  key_length INTEGER := 32;
  chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  result TEXT := 'pk_';
  i INTEGER;
BEGIN
  FOR i IN 1..key_length LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- Function to validate API key and check rate limits
CREATE OR REPLACE FUNCTION public.validate_api_key(api_key TEXT)
RETURNS TABLE(
  is_valid BOOLEAN,
  client_id UUID,
  permissions JSONB,
  rate_limit_exceeded BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  key_record RECORD;
  usage_count INTEGER;
BEGIN
  -- Find the API key
  SELECT ak.client_id, ak.permissions, ak.rate_limit_per_hour, ak.status
  INTO key_record
  FROM public.api_keys ak
  WHERE ak.key_hash = encode(digest(api_key, 'sha256'), 'hex')
  AND ak.status = 'active'
  AND (ak.expires_at IS NULL OR ak.expires_at > NOW());

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::UUID, '{}'::JSONB, false;
    RETURN;
  END IF;

  -- Check rate limit
  SELECT COUNT(*)
  INTO usage_count
  FROM public.api_usage_logs aul
  JOIN public.api_keys ak ON ak.id = aul.api_key_id
  WHERE ak.key_hash = encode(digest(api_key, 'sha256'), 'hex')
  AND aul.created_at > NOW() - INTERVAL '1 hour';

  -- Update last used timestamp
  UPDATE public.api_keys 
  SET last_used_at = NOW()
  WHERE key_hash = encode(digest(api_key, 'sha256'), 'hex');

  RETURN QUERY SELECT 
    true,
    key_record.client_id,
    key_record.permissions,
    usage_count >= key_record.rate_limit_per_hour;
END;
$$;

-- Function to log API usage
CREATE OR REPLACE FUNCTION public.log_api_usage(
  api_key TEXT,
  endpoint TEXT,
  method TEXT,
  ip_address TEXT DEFAULT NULL,
  user_agent TEXT DEFAULT NULL,
  response_status INTEGER DEFAULT NULL,
  response_time_ms INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  key_id UUID;
BEGIN
  SELECT ak.id INTO key_id
  FROM public.api_keys ak
  WHERE ak.key_hash = encode(digest(api_key, 'sha256'), 'hex');

  IF FOUND THEN
    INSERT INTO public.api_usage_logs (
      api_key_id, endpoint, method, ip_address, user_agent, response_status, response_time_ms
    ) VALUES (
      key_id, endpoint, method, ip_address::INET, user_agent, response_status, response_time_ms
    );
  END IF;
END;
$$;

-- Create indexes for performance
CREATE INDEX idx_api_keys_client_id ON public.api_keys(client_id);
CREATE INDEX idx_api_keys_key_hash ON public.api_keys(key_hash);
CREATE INDEX idx_api_keys_status ON public.api_keys(status);
CREATE INDEX idx_api_usage_logs_api_key_id ON public.api_usage_logs(api_key_id);
CREATE INDEX idx_api_usage_logs_created_at ON public.api_usage_logs(created_at);
CREATE INDEX idx_webhooks_client_id ON public.webhooks(client_id);
CREATE INDEX idx_webhooks_event_id ON public.webhooks(event_id);
CREATE INDEX idx_webhook_deliveries_webhook_id ON public.webhook_deliveries(webhook_id);
