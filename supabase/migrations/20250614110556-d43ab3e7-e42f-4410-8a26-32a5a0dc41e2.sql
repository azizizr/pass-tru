
-- Add path_prefix column to events table
ALTER TABLE public.events 
ADD COLUMN path_prefix TEXT UNIQUE;

-- Add a constraint to ensure path_prefix follows URL-friendly format
ALTER TABLE public.events 
ADD CONSTRAINT path_prefix_format CHECK (path_prefix ~ '^[a-z0-9-]+$');

-- Create an index for better performance on path_prefix lookups
CREATE INDEX idx_events_path_prefix ON public.events(path_prefix);
