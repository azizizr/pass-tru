
-- Update the handle_new_user function to use the new Super Admin email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    CASE 
      WHEN NEW.email = 'work.ahmadazizi@gmail.com' THEN 'super_admin'::user_role
      ELSE COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'client')
    END
  );
  RETURN NEW;
END;
$function$;
