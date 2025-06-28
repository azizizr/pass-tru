
-- Add public check-in related fields to events table
ALTER TABLE public.events 
ADD COLUMN IF NOT EXISTS public_checkin_enabled boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS custom_message text,
ADD COLUMN IF NOT EXISTS path_prefix text;

-- Create a function to find attendee by unique ID and event
CREATE OR REPLACE FUNCTION public.find_attendee_for_checkin(
  event_slug text,
  attendee_unique_id text
)
RETURNS TABLE (
  attendee_id uuid,
  attendee_name text,
  attendee_email text,
  attendee_status attendee_status,
  event_name text,
  event_date date,
  event_venue text,
  custom_message text
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT 
    a.id as attendee_id,
    a.full_name as attendee_name,
    a.email as attendee_email,
    a.status as attendee_status,
    e.name as event_name,
    e.date as event_date,
    e.venue as event_venue,
    e.custom_message
  FROM public.attendees a
  JOIN public.events e ON a.event_id = e.id
  WHERE e.slug = event_slug 
  AND a.unique_id = attendee_unique_id
  AND e.public_checkin_enabled = true;
$$;

-- Create a function for public self check-in
CREATE OR REPLACE FUNCTION public.public_self_checkin(
  event_slug text,
  attendee_unique_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  attendee_record record;
  result jsonb;
BEGIN
  -- Find the attendee
  SELECT INTO attendee_record
    a.id, a.full_name, a.status, e.name as event_name, e.custom_message
  FROM public.attendees a
  JOIN public.events e ON a.event_id = e.id
  WHERE e.slug = event_slug 
  AND a.unique_id = attendee_unique_id
  AND e.public_checkin_enabled = true;

  -- Check if attendee was found
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Attendee not found or check-in not enabled for this event'
    );
  END IF;

  -- Check if already checked in
  IF attendee_record.status = 'checked_in' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Already checked in',
      'attendee_name', attendee_record.full_name
    );
  END IF;

  -- Perform check-in
  UPDATE public.attendees 
  SET 
    status = 'checked_in',
    checked_in_at = now(),
    checkin_method = 'self_checkin'
  WHERE id = attendee_record.id;

  -- Return success result
  RETURN jsonb_build_object(
    'success', true,
    'attendee_name', attendee_record.full_name,
    'event_name', attendee_record.event_name,
    'custom_message', attendee_record.custom_message
  );
END;
$$;

-- Create RLS policies for public check-in functions
CREATE POLICY "Allow public check-in lookup" ON public.attendees
  FOR SELECT USING (true);

CREATE POLICY "Allow public self check-in update" ON public.attendees
  FOR UPDATE USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow public event lookup" ON public.events
  FOR SELECT USING (public_checkin_enabled = true);
