
-- Add template storage and enhanced email features

-- Create email templates table for custom template storage
CREATE TABLE public.email_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  subject TEXT NOT NULL,
  content TEXT NOT NULL,
  template_type VARCHAR(50) NOT NULL,
  variables JSONB DEFAULT '[]'::JSONB,
  is_default BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enhance email_settings table with branding options
ALTER TABLE public.email_settings ADD COLUMN IF NOT EXISTS email_logo_url TEXT;
ALTER TABLE public.email_settings ADD COLUMN IF NOT EXISTS email_header_color TEXT DEFAULT '#3b82f6';
ALTER TABLE public.email_settings ADD COLUMN IF NOT EXISTS email_footer_text TEXT;
ALTER TABLE public.email_settings ADD COLUMN IF NOT EXISTS custom_domain TEXT;
ALTER TABLE public.email_settings ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'UTC';

-- Add template customization to email_campaigns
ALTER TABLE public.email_campaigns ADD COLUMN IF NOT EXISTS custom_template_id UUID REFERENCES public.email_templates(id);
ALTER TABLE public.email_campaigns ADD COLUMN IF NOT EXISTS brand_settings JSONB DEFAULT '{}'::JSONB;

-- Enhance attendees table with better QR code storage
ALTER TABLE public.attendees ADD COLUMN IF NOT EXISTS qr_code_url TEXT;
ALTER TABLE public.attendees ADD COLUMN IF NOT EXISTS portal_access_enabled BOOLEAN DEFAULT false;

-- Create RLS policies for email templates
ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own email templates" ON public.email_templates
  FOR SELECT USING (
    client_id = auth.uid() OR auth.uid() IN (
      SELECT id FROM public.profiles WHERE role = 'super_admin'
    )
  );

CREATE POLICY "Users can create their own email templates" ON public.email_templates
  FOR INSERT WITH CHECK (
    client_id = auth.uid() OR auth.uid() IN (
      SELECT id FROM public.profiles WHERE role = 'super_admin'
    )
  );

CREATE POLICY "Users can update their own email templates" ON public.email_templates
  FOR UPDATE USING (
    client_id = auth.uid() OR auth.uid() IN (
      SELECT id FROM public.profiles WHERE role = 'super_admin'
    )
  );

CREATE POLICY "Users can delete their own email templates" ON public.email_templates
  FOR DELETE USING (
    client_id = auth.uid() OR auth.uid() IN (
      SELECT id FROM public.profiles WHERE role = 'super_admin'
    )
  );

-- Create indexes for better performance
CREATE INDEX idx_email_templates_client_id ON public.email_templates(client_id);
CREATE INDEX idx_email_templates_type ON public.email_templates(template_type);
CREATE INDEX idx_email_templates_active ON public.email_templates(is_active);

-- Add trigger for updated_at on email_templates
CREATE TRIGGER update_email_templates_updated_at BEFORE UPDATE
    ON public.email_templates FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default templates for new clients
INSERT INTO public.email_templates (client_id, name, subject, template_type, content, variables, is_default) VALUES
(NULL, 'Default Confirmation', 'Your Event Pass is Ready – {event_name}', 'confirmation', 
'Hello {attendee_name},

You''re all set for {event_name}! Your event pass is ready.

Event Details:
- Date: {event_date}
- Venue: {event_venue}
- Your Unique ID: {unique_id}

{qr_code}

{calendar_invite}

Looking forward to seeing you there!

Best regards,
{organizer_name}', 
'["attendee_name", "event_name", "event_date", "event_venue", "unique_id", "qr_code", "calendar_invite", "organizer_name"]'::JSONB, 
true),

(NULL, 'Default Welcome', 'Welcome to {event_name}!', 'welcome',
'Dear {attendee_name},

Welcome to {event_name}! We''re excited to have you join us.

Event Information:
- Date: {event_date}
- Venue: {event_venue}
- Check-in starts: {checkin_time}

{custom_message}

Your portal: {portal_url}

Best regards,
{organizer_name}',
'["attendee_name", "event_name", "event_date", "event_venue", "checkin_time", "custom_message", "portal_url", "organizer_name"]'::JSONB,
true),

(NULL, 'Default Post Check-in', 'Successfully Checked In – {event_name}', 'post_checkin',
'Hello {attendee_name},

You''ve been successfully checked in to {event_name}!

{seat_assignment}

Your personalized portal is now active: {portal_url}

Enjoy the event!

Best regards,
{organizer_name}',
'["attendee_name", "event_name", "seat_assignment", "portal_url", "organizer_name"]'::JSONB,
true);
