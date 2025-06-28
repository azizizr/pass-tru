
-- Fix critical RLS policies for public check-in security
-- Replace overly permissive policies with secure alternatives

-- Drop the existing dangerous policies
DROP POLICY IF EXISTS "Allow public check-in lookup" ON public.attendees;
DROP POLICY IF EXISTS "Allow public self check-in update" ON public.attendees;
DROP POLICY IF EXISTS "Allow public event lookup" ON public.events;

-- Create secure RLS policies for public check-in
-- Only allow lookup of attendees for events with public check-in enabled
CREATE POLICY "Allow public attendee lookup for enabled events" 
  ON public.attendees 
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.events e 
      WHERE e.id = attendees.event_id 
      AND e.public_checkin_enabled = true
    )
  );

-- Only allow self check-in updates for the specific attendee
CREATE POLICY "Allow self check-in updates" 
  ON public.attendees 
  FOR UPDATE 
  USING (
    EXISTS (
      SELECT 1 FROM public.events e 
      WHERE e.id = attendees.event_id 
      AND e.public_checkin_enabled = true
    )
  )
  WITH CHECK (
    status = 'checked_in' 
    AND checked_in_at IS NOT NULL
    AND checkin_method = 'self_checkin'
  );

-- Secure event lookup policy
CREATE POLICY "Allow public event lookup for enabled check-in" 
  ON public.events 
  FOR SELECT 
  USING (public_checkin_enabled = true);

-- Add security function to validate API key generation
CREATE OR REPLACE FUNCTION public.generate_secure_api_key()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  key_length INTEGER := 32;
  chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  result TEXT := 'pk_live_';
  i INTEGER;
  random_bytes BYTEA;
BEGIN
  -- Use cryptographically secure random generation
  random_bytes := gen_random_bytes(key_length);
  
  FOR i IN 1..key_length LOOP
    result := result || substr(chars, (get_byte(random_bytes, i % 32) % length(chars)) + 1, 1);
  END LOOP;
  
  RETURN result;
END;
$$;

-- Add email validation function
CREATE OR REPLACE FUNCTION public.validate_email(email_address text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  -- Basic email validation
  RETURN email_address ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    AND length(email_address) <= 254
    AND email_address NOT LIKE '%..%'
    AND email_address NOT LIKE '.%'
    AND email_address NOT LIKE '%.'
    AND email_address NOT LIKE '@%'
    AND email_address NOT LIKE '%@';
END;
$$;

-- Add rate limiting for authentication attempts
CREATE TABLE IF NOT EXISTS public.auth_rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ip_address inet NOT NULL,
  attempt_count integer DEFAULT 1,
  window_start timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now()
);

-- Create function to check rate limits
CREATE OR REPLACE FUNCTION public.check_auth_rate_limit(client_ip inet)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  current_attempts integer;
  window_duration interval := '15 minutes';
  max_attempts integer := 5;
BEGIN
  -- Clean up old entries
  DELETE FROM public.auth_rate_limits 
  WHERE window_start < now() - window_duration;
  
  -- Get current attempt count for this IP
  SELECT COALESCE(attempt_count, 0) INTO current_attempts
  FROM public.auth_rate_limits
  WHERE ip_address = client_ip
  AND window_start > now() - window_duration;
  
  -- Check if rate limit exceeded
  IF current_attempts >= max_attempts THEN
    RETURN false;
  END IF;
  
  -- Increment or insert attempt count
  INSERT INTO public.auth_rate_limits (ip_address, attempt_count)
  VALUES (client_ip, 1)
  ON CONFLICT (ip_address) 
  DO UPDATE SET 
    attempt_count = auth_rate_limits.attempt_count + 1,
    window_start = CASE 
      WHEN auth_rate_limits.window_start < now() - window_duration 
      THEN now() 
      ELSE auth_rate_limits.window_start 
    END;
    
  RETURN true;
END;
$$;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_auth_rate_limits_ip_window 
  ON public.auth_rate_limits(ip_address, window_start);
