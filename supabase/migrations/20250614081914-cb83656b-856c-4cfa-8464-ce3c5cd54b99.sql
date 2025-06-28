
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create enum types
CREATE TYPE user_role AS ENUM ('super_admin', 'client');
CREATE TYPE event_status AS ENUM ('active', 'suspended', 'completed');
CREATE TYPE client_status AS ENUM ('active', 'suspended');
CREATE TYPE attendee_status AS ENUM ('registered', 'checked_in');
CREATE TYPE checkin_method AS ENUM ('qr_scan', 'manual', 'self_checkin');

-- Create profiles table (extends auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT,
  organisation TEXT,
  role user_role NOT NULL DEFAULT 'client',
  status client_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create events table
CREATE TABLE public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  date DATE NOT NULL,
  venue TEXT NOT NULL,
  attendee_limit INTEGER NOT NULL,
  status event_status NOT NULL DEFAULT 'active',
  logo_url TEXT,
  poster_url TEXT,
  public_checkin_enabled BOOLEAN DEFAULT FALSE,
  custom_message TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create client_events table (many-to-many relationship)
CREATE TABLE public.client_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(client_id, event_id)
);

-- Create attendees table
CREATE TABLE public.attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  unique_id TEXT NOT NULL,
  qr_code TEXT NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  status attendee_status NOT NULL DEFAULT 'registered',
  custom_fields JSONB DEFAULT '{}',
  checked_in_at TIMESTAMP WITH TIME ZONE,
  checked_in_by UUID REFERENCES auth.users(id),
  checkin_method checkin_method,
  portal_activated BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(event_id, unique_id),
  UNIQUE(event_id, email)
);

-- Create audit_logs table
CREATE TABLE public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  event_id UUID REFERENCES public.events(id),
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create event_content table for branding and files
CREATE TABLE public.event_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  content_type TEXT NOT NULL, -- 'logo', 'poster', 'floorplan', 'document'
  file_name TEXT NOT NULL,
  file_url TEXT NOT NULL,
  file_size BIGINT,
  mime_type TEXT,
  uploaded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_content ENABLE ROW LEVEL SECURITY;

-- Create security definer functions to avoid RLS recursion
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS user_role
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role = 'super_admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.can_access_event(event_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.client_events ce
    JOIN public.profiles p ON p.id = auth.uid()
    WHERE ce.event_id = $1 
    AND (ce.client_id = auth.uid() OR p.role = 'super_admin')
  );
$$;

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Super admins can view all profiles" ON public.profiles
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Super admins can manage all profiles" ON public.profiles
  FOR ALL USING (public.is_super_admin());

-- RLS Policies for events
CREATE POLICY "Super admins can manage all events" ON public.events
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can view assigned events" ON public.events
  FOR SELECT USING (public.can_access_event(id));

CREATE POLICY "Clients can update assigned events" ON public.events
  FOR UPDATE USING (public.can_access_event(id));

-- RLS Policies for client_events
CREATE POLICY "Super admins can manage client events" ON public.client_events
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can view their assignments" ON public.client_events
  FOR SELECT USING (auth.uid() = client_id);

-- RLS Policies for attendees
CREATE POLICY "Super admins can manage all attendees" ON public.attendees
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can manage event attendees" ON public.attendees
  FOR ALL USING (public.can_access_event(event_id));

-- RLS Policies for audit_logs
CREATE POLICY "Super admins can view all audit logs" ON public.audit_logs
  FOR SELECT USING (public.is_super_admin());

CREATE POLICY "Users can view their own audit logs" ON public.audit_logs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Authenticated users can insert audit logs" ON public.audit_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- RLS Policies for event_content
CREATE POLICY "Super admins can manage all content" ON public.event_content
  FOR ALL USING (public.is_super_admin());

CREATE POLICY "Clients can manage event content" ON public.event_content
  FOR ALL USING (public.can_access_event(event_id));

-- Create function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'client')
  );
  RETURN NEW;
END;
$$;

-- Create trigger for new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create function to generate unique attendee ID
CREATE OR REPLACE FUNCTION public.generate_unique_attendee_id(event_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  new_id TEXT;
  counter INTEGER := 0;
BEGIN
  LOOP
    new_id := LPAD((FLOOR(RANDOM() * 1000000))::TEXT, 6, '0');
    
    IF NOT EXISTS (
      SELECT 1 FROM public.attendees 
      WHERE attendees.event_id = generate_unique_attendee_id.event_id 
      AND unique_id = new_id
    ) THEN
      RETURN new_id;
    END IF;
    
    counter := counter + 1;
    IF counter > 100 THEN
      RAISE EXCEPTION 'Unable to generate unique ID after 100 attempts';
    END IF;
  END LOOP;
END;
$$;

-- Create indexes for performance
CREATE INDEX idx_profiles_role ON public.profiles(role);
CREATE INDEX idx_events_slug ON public.events(slug);
CREATE INDEX idx_events_status ON public.events(status);
CREATE INDEX idx_client_events_client_id ON public.client_events(client_id);
CREATE INDEX idx_client_events_event_id ON public.client_events(event_id);
CREATE INDEX idx_attendees_event_id ON public.attendees(event_id);
CREATE INDEX idx_attendees_unique_id ON public.attendees(unique_id);
CREATE INDEX idx_attendees_status ON public.attendees(status);
CREATE INDEX idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX idx_audit_logs_event_id ON public.audit_logs(event_id);
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs(created_at);
