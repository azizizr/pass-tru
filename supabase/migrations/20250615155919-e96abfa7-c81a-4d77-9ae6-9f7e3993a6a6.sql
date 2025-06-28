
-- Create storage buckets for file management
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('brand-assets', 'brand-assets', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml']),
  ('event-content', 'event-content', true, 52428800, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml', 'application/pdf', 'text/plain']),
  ('email-attachments', 'email-attachments', false, 10485760, ARRAY['image/jpeg', 'image/png', 'image/gif', 'application/pdf']),
  ('user-uploads', 'user-uploads', false, 20971520, ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf', 'text/plain', 'text/csv'])
ON CONFLICT (id) DO NOTHING;

-- Create file_metadata table
CREATE TABLE IF NOT EXISTS public.file_metadata (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_size BIGINT NOT NULL,
  mime_type TEXT NOT NULL,
  bucket_name TEXT NOT NULL,
  file_type TEXT NOT NULL,
  description TEXT,
  tags TEXT[],
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on file_metadata
ALTER TABLE public.file_metadata ENABLE ROW LEVEL SECURITY;

-- RLS Policies for file_metadata
CREATE POLICY "Super admins can manage all files" ON public.file_metadata
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Users can manage their own files" ON public.file_metadata
  FOR ALL USING (auth.uid() = user_id);

-- Storage policies for brand-assets bucket
CREATE POLICY "Super admins can upload brand assets" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'brand-assets' AND 
    public.is_super_admin()
  );

CREATE POLICY "Super admins can update brand assets" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'brand-assets' AND 
    public.is_super_admin()
  );

CREATE POLICY "Super admins can delete brand assets" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'brand-assets' AND 
    public.is_super_admin()
  );

CREATE POLICY "Brand assets are publicly readable" ON storage.objects
  FOR SELECT USING (bucket_id = 'brand-assets');

-- Storage policies for event-content bucket
CREATE POLICY "Users can upload event content" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'event-content' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can update their event content" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'event-content' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete their event content" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'event-content' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Event content is publicly readable" ON storage.objects
  FOR SELECT USING (bucket_id = 'event-content');

-- Storage policies for email-attachments bucket
CREATE POLICY "Users can upload email attachments" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'email-attachments' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can access their email attachments" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'email-attachments' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete their email attachments" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'email-attachments' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

-- Storage policies for user-uploads bucket
CREATE POLICY "Users can upload files" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'user-uploads' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can access their uploads" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'user-uploads' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete their uploads" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'user-uploads' AND 
    auth.uid()::text = (storage.foldername(name))[1]
  );

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_file_metadata_user_id ON public.file_metadata(user_id);
CREATE INDEX IF NOT EXISTS idx_file_metadata_event_id ON public.file_metadata(event_id);
CREATE INDEX IF NOT EXISTS idx_file_metadata_file_type ON public.file_metadata(file_type);
CREATE INDEX IF NOT EXISTS idx_file_metadata_is_active ON public.file_metadata(is_active);
