
-- Create brand_settings table for white-labeling
CREATE TABLE public.brand_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  primary_color TEXT NOT NULL DEFAULT '#3b82f6',
  secondary_color TEXT NOT NULL DEFAULT '#8b5cf6',
  logo_url TEXT,
  company_name TEXT NOT NULL,
  custom_domain TEXT,
  email_from_name TEXT NOT NULL,
  email_from_address TEXT,
  custom_css TEXT,
  favicon_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(client_id)
);

-- Enable RLS
ALTER TABLE public.brand_settings ENABLE ROW LEVEL SECURITY;

-- Create policies for brand_settings
CREATE POLICY "Clients can view their own brand settings" 
  ON public.brand_settings 
  FOR SELECT 
  USING (auth.uid() = client_id);

CREATE POLICY "Clients can insert their own brand settings" 
  ON public.brand_settings 
  FOR INSERT 
  WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Clients can update their own brand settings" 
  ON public.brand_settings 
  FOR UPDATE 
  USING (auth.uid() = client_id);

-- Super admins can view all brand settings
CREATE POLICY "Super admins can view all brand settings" 
  ON public.brand_settings 
  FOR ALL
  USING (public.is_super_admin());

-- Create storage bucket for brand assets
INSERT INTO storage.buckets (id, name, public) 
VALUES ('brand-assets', 'brand-assets', true);

-- Create storage policies for brand assets
CREATE POLICY "Clients can upload their brand assets" 
  ON storage.objects 
  FOR INSERT 
  WITH CHECK (
    bucket_id = 'brand-assets' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Anyone can view brand assets" 
  ON storage.objects 
  FOR SELECT 
  USING (bucket_id = 'brand-assets');

CREATE POLICY "Clients can update their brand assets" 
  ON storage.objects 
  FOR UPDATE 
  USING (
    bucket_id = 'brand-assets' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Clients can delete their brand assets" 
  ON storage.objects 
  FOR DELETE 
  USING (
    bucket_id = 'brand-assets' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
