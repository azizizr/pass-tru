
-- Since we can't directly insert into auth.users, let's create a function 
-- that will be triggered when a user signs up to automatically assign super_admin role
-- to the specific demo admin email

-- First, let's update the handle_new_user function to check for the demo admin email
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
      WHEN NEW.email = 'admin@passtru.com' THEN 'super_admin'::user_role
      ELSE COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'client')
    END
  );
  RETURN NEW;
END;
$function$;

-- Also, let's make sure we have the trigger in place
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
