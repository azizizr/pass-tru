
-- Create subscription plans table
CREATE TABLE public.subscription_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  price_monthly DECIMAL(10,2) NOT NULL,
  price_yearly DECIMAL(10,2),
  max_events INTEGER,
  max_attendees_per_event INTEGER,
  max_storage_gb INTEGER DEFAULT 5,
  features JSONB DEFAULT '[]'::jsonb,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create client subscriptions table
CREATE TABLE public.client_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan_id UUID REFERENCES public.subscription_plans(id),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'suspended', 'past_due')),
  current_period_start TIMESTAMP WITH TIME ZONE DEFAULT now(),
  current_period_end TIMESTAMP WITH TIME ZONE DEFAULT now() + INTERVAL '1 month',
  billing_cycle TEXT DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly')),
  stripe_subscription_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create client usage tracking table
CREATE TABLE public.client_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  month_year DATE NOT NULL, -- YYYY-MM-01 format
  events_created INTEGER DEFAULT 0,
  total_attendees INTEGER DEFAULT 0,
  storage_used_gb DECIMAL(10,3) DEFAULT 0,
  api_calls_made INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(client_id, month_year)
);

-- Extend brand_settings table with advanced features
ALTER TABLE public.brand_settings 
ADD COLUMN white_label_enabled BOOLEAN DEFAULT false,
ADD COLUMN custom_login_page_url TEXT,
ADD COLUMN custom_footer_text TEXT,
ADD COLUMN social_media_links JSONB DEFAULT '{}'::jsonb,
ADD COLUMN mobile_app_icon_url TEXT,
ADD COLUMN mobile_splash_screen_url TEXT,
ADD COLUMN advanced_css TEXT,
ADD COLUMN email_templates JSONB DEFAULT '{}'::jsonb;

-- Create SSO configurations table
CREATE TABLE public.sso_configurations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('saml', 'oauth', 'oidc')),
  provider_name TEXT NOT NULL,
  configuration JSONB NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create audit logs table for compliance
CREATE TABLE public.compliance_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_id UUID,
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  details JSONB DEFAULT '{}'::jsonb,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create client billing history table
CREATE TABLE public.billing_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  subscription_id UUID REFERENCES public.client_subscriptions(id),
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'USD',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  stripe_invoice_id TEXT,
  billing_period_start TIMESTAMP WITH TIME ZONE,
  billing_period_end TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Insert default subscription plans
INSERT INTO public.subscription_plans (name, description, price_monthly, price_yearly, max_events, max_attendees_per_event, max_storage_gb, features) VALUES
('Starter', 'Perfect for small events', 29.00, 290.00, 5, 500, 5, '["Basic Analytics", "Email Support", "QR Code Check-in"]'::jsonb),
('Professional', 'Ideal for growing businesses', 99.00, 990.00, 25, 2000, 25, '["Advanced Analytics", "Priority Support", "Custom Branding", "API Access"]'::jsonb),
('Enterprise', 'For large organizations', 299.00, 2990.00, -1, -1, 100, '["Unlimited Events", "White Label", "SSO", "Dedicated Support", "Custom Integration"]'::jsonb);

-- Enable RLS on new tables
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sso_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_history ENABLE ROW LEVEL SECURITY;

-- RLS policies for subscription plans (public read for all authenticated users)
CREATE POLICY "Authenticated users can view subscription plans" 
  ON public.subscription_plans FOR SELECT 
  TO authenticated 
  USING (is_active = true);

-- RLS policies for client subscriptions
CREATE POLICY "Clients can view their own subscriptions" 
  ON public.client_subscriptions FOR SELECT 
  TO authenticated 
  USING (client_id = auth.uid() OR public.is_super_admin());

CREATE POLICY "Super admins can manage all subscriptions" 
  ON public.client_subscriptions FOR ALL 
  TO authenticated 
  USING (public.is_super_admin());

-- RLS policies for client usage
CREATE POLICY "Clients can view their own usage" 
  ON public.client_usage FOR SELECT 
  TO authenticated 
  USING (client_id = auth.uid() OR public.is_super_admin());

CREATE POLICY "System can update usage for all clients" 
  ON public.client_usage FOR ALL 
  TO authenticated 
  USING (public.is_super_admin());

-- RLS policies for SSO configurations
CREATE POLICY "Clients can manage their own SSO" 
  ON public.sso_configurations FOR ALL 
  TO authenticated 
  USING (client_id = auth.uid() OR public.is_super_admin());

-- RLS policies for compliance audit logs
CREATE POLICY "Clients can view their own audit logs" 
  ON public.compliance_audit_logs FOR SELECT 
  TO authenticated 
  USING (client_id = auth.uid() OR public.is_super_admin());

CREATE POLICY "System can insert audit logs" 
  ON public.compliance_audit_logs FOR INSERT 
  TO authenticated 
  WITH CHECK (true);

-- RLS policies for billing history
CREATE POLICY "Clients can view their own billing history" 
  ON public.billing_history FOR SELECT 
  TO authenticated 
  USING (client_id = auth.uid() OR public.is_super_admin());

CREATE POLICY "Super admins can manage all billing" 
  ON public.billing_history FOR ALL 
  TO authenticated 
  USING (public.is_super_admin());

-- Create function to check client subscription limits
CREATE OR REPLACE FUNCTION public.check_client_limits(client_id UUID, limit_type TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  subscription_record RECORD;
  usage_record RECORD;
  current_month DATE;
  result JSONB;
BEGIN
  current_month := date_trunc('month', CURRENT_DATE)::DATE;
  
  -- Get client subscription
  SELECT sp.*, cs.status as subscription_status
  INTO subscription_record
  FROM public.client_subscriptions cs
  JOIN public.subscription_plans sp ON cs.plan_id = sp.id
  WHERE cs.client_id = check_client_limits.client_id
  AND cs.status = 'active'
  ORDER BY cs.created_at DESC
  LIMIT 1;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'No active subscription');
  END IF;
  
  -- Get current usage
  SELECT * INTO usage_record
  FROM public.client_usage
  WHERE client_usage.client_id = check_client_limits.client_id
  AND month_year = current_month;
  
  IF NOT FOUND THEN
    -- Create usage record if doesn't exist
    INSERT INTO public.client_usage (client_id, month_year)
    VALUES (check_client_limits.client_id, current_month);
    usage_record.events_created := 0;
    usage_record.total_attendees := 0;
    usage_record.storage_used_gb := 0;
    usage_record.api_calls_made := 0;
  END IF;
  
  -- Check limits based on type
  CASE limit_type
    WHEN 'events' THEN
      IF subscription_record.max_events = -1 THEN
        result := jsonb_build_object('allowed', true, 'unlimited', true);
      ELSE
        result := jsonb_build_object(
          'allowed', usage_record.events_created < subscription_record.max_events,
          'current', usage_record.events_created,
          'limit', subscription_record.max_events
        );
      END IF;
    WHEN 'storage' THEN
      result := jsonb_build_object(
        'allowed', usage_record.storage_used_gb < subscription_record.max_storage_gb,
        'current', usage_record.storage_used_gb,
        'limit', subscription_record.max_storage_gb
      );
    ELSE
      result := jsonb_build_object('allowed', true);
  END CASE;
  
  RETURN result;
END;
$$;

-- Function to log compliance actions
CREATE OR REPLACE FUNCTION public.log_compliance_action(
  p_client_id UUID,
  p_user_id UUID,
  p_action TEXT,
  p_resource_type TEXT,
  p_resource_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.compliance_audit_logs (
    client_id, user_id, action, resource_type, resource_id, details
  ) VALUES (
    p_client_id, p_user_id, p_action, p_resource_type, p_resource_id, p_details
  );
END;
$$;
