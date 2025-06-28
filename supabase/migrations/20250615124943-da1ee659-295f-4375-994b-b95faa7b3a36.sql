
-- Add event_category column to events table
ALTER TABLE public.events 
ADD COLUMN event_category TEXT;

-- Update existing events to have a default category
UPDATE public.events 
SET event_category = 'Conference' 
WHERE event_category IS NULL;

-- Make event_category required for new events
ALTER TABLE public.events 
ALTER COLUMN event_category SET NOT NULL;

-- Add a check constraint for valid categories
ALTER TABLE public.events 
ADD CONSTRAINT events_category_check 
CHECK (event_category IN ('Conference', 'Workshop', 'Seminar', 'Networking', 'Training', 'Webinar', 'Other'));
