
-- Check if storage buckets exist, if not create them
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('brand-assets', 'brand-assets', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml']),
  ('event-content', 'event-content', true, 52428800, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml', 'application/pdf', 'text/plain']),
  ('email-attachments', 'email-attachments', false, 10485760, ARRAY['image/jpeg', 'image/png', 'image/gif', 'application/pdf']),
  ('user-uploads', 'user-uploads', false, 20971520, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf', 'text/plain', 'text/csv'])
ON CONFLICT (id) DO NOTHING;

-- Add performance indexes for frequently queried columns
CREATE INDEX IF NOT EXISTS idx_attendees_event_status ON public.attendees(event_id, status);
CREATE INDEX IF NOT EXISTS idx_email_campaigns_event_status_date ON public.email_campaigns(event_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_date ON public.audit_logs(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_api_usage_logs_key_date ON public.api_usage_logs(api_key_id, created_at);
CREATE INDEX IF NOT EXISTS idx_attendees_unique_id ON public.attendees(unique_id);
CREATE INDEX IF NOT EXISTS idx_events_slug ON public.events(slug);
CREATE INDEX IF NOT EXISTS idx_events_status ON public.events(status);

-- Add indexes for file_metadata table for better performance
CREATE INDEX IF NOT EXISTS idx_file_metadata_user_id ON public.file_metadata(user_id);
CREATE INDEX IF NOT EXISTS idx_file_metadata_event_id ON public.file_metadata(event_id);
CREATE INDEX IF NOT EXISTS idx_file_metadata_file_type ON public.file_metadata(file_type);
CREATE INDEX IF NOT EXISTS idx_file_metadata_is_active ON public.file_metadata(is_active);
