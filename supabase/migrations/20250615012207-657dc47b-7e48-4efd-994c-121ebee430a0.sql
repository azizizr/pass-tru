
-- Create email campaigns table for tracking sent email campaigns
CREATE TABLE public.email_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  subject TEXT NOT NULL,
  content TEXT NOT NULL,
  template_type VARCHAR(50),
  recipients_count INTEGER DEFAULT 0,
  sent_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  status VARCHAR(20) DEFAULT 'draft',
  scheduled_for TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create email delivery logs table for tracking individual email deliveries
CREATE TABLE public.email_delivery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID REFERENCES public.email_campaigns(id) ON DELETE CASCADE,
  attendee_id UUID REFERENCES public.attendees(id) ON DELETE CASCADE,
  email_address TEXT NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  clicked_at TIMESTAMPTZ,
  error_message TEXT,
  external_id TEXT, -- For tracking with email provider (Resend)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create email settings table for SMTP configuration
CREATE TABLE public.email_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  smtp_host TEXT,
  smtp_port INTEGER,
  smtp_username TEXT,
  smtp_password TEXT,
  from_email TEXT NOT NULL,
  from_name TEXT NOT NULL,
  reply_to_email TEXT,
  is_active BOOLEAN DEFAULT true,
  provider VARCHAR(50) DEFAULT 'resend',
  api_key TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add RLS policies for email campaigns
ALTER TABLE public.email_campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view campaigns for their events" ON public.email_campaigns
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.client_events ce
      WHERE ce.event_id = email_campaigns.event_id
      AND (ce.client_id = auth.uid() OR auth.uid() IN (
        SELECT id FROM public.profiles WHERE role = 'super_admin'
      ))
    )
  );

CREATE POLICY "Users can create campaigns for their events" ON public.email_campaigns
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.client_events ce
      WHERE ce.event_id = email_campaigns.event_id
      AND (ce.client_id = auth.uid() OR auth.uid() IN (
        SELECT id FROM public.profiles WHERE role = 'super_admin'
      ))
    )
  );

CREATE POLICY "Users can update campaigns for their events" ON public.email_campaigns
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.client_events ce
      WHERE ce.event_id = email_campaigns.event_id
      AND (ce.client_id = auth.uid() OR auth.uid() IN (
        SELECT id FROM public.profiles WHERE role = 'super_admin'
      ))
    )
  );

-- Add RLS policies for email delivery logs
ALTER TABLE public.email_delivery_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view delivery logs for their campaigns" ON public.email_delivery_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.email_campaigns ec
      JOIN public.client_events ce ON ce.event_id = ec.event_id
      WHERE ec.id = email_delivery_logs.campaign_id
      AND (ce.client_id = auth.uid() OR auth.uid() IN (
        SELECT id FROM public.profiles WHERE role = 'super_admin'
      ))
    )
  );

-- Add RLS policies for email settings
ALTER TABLE public.email_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own email settings" ON public.email_settings
  FOR ALL USING (
    client_id = auth.uid() OR auth.uid() IN (
      SELECT id FROM public.profiles WHERE role = 'super_admin'
    )
  );

-- Create indexes for better performance
CREATE INDEX idx_email_campaigns_event_id ON public.email_campaigns(event_id);
CREATE INDEX idx_email_campaigns_status ON public.email_campaigns(status);
CREATE INDEX idx_email_campaigns_scheduled_for ON public.email_campaigns(scheduled_for);
CREATE INDEX idx_email_delivery_logs_campaign_id ON public.email_delivery_logs(campaign_id);
CREATE INDEX idx_email_delivery_logs_attendee_id ON public.email_delivery_logs(attendee_id);
CREATE INDEX idx_email_delivery_logs_status ON public.email_delivery_logs(status);
CREATE INDEX idx_email_settings_client_id ON public.email_settings(client_id);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers for updated_at
CREATE TRIGGER update_email_campaigns_updated_at BEFORE UPDATE
    ON public.email_campaigns FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_email_settings_updated_at BEFORE UPDATE
    ON public.email_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
