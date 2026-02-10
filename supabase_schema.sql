-- Supabase Schema for Neuro EMR App
-- Run this in Supabase Dashboard → SQL Editor → New Query

-- Enable UUID extension (usually already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS TABLE (extends Supabase auth.users)
-- ============================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'secretary' CHECK (role IN ('physician', 'nurse', 'secretary')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PATIENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_english TEXT NOT NULL DEFAULT '',
    name_arabic TEXT DEFAULT '',
    dob DATE,
    gender TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    mrn TEXT DEFAULT '',
    national_id TEXT DEFAULT '',
    passport TEXT DEFAULT '',
    blood_type TEXT DEFAULT '',
    insurance_provider TEXT DEFAULT '',
    insurance_policy_number TEXT DEFAULT '',
    emergency_contact_name TEXT DEFAULT '',
    emergency_contact_phone TEXT DEFAULT '',
    address TEXT DEFAULT '',
    allergies TEXT DEFAULT '',
    chronic_conditions TEXT DEFAULT '',
    surgical_history TEXT DEFAULT '',
    family_history TEXT DEFAULT '',
    social_history TEXT DEFAULT '',
    current_medications TEXT DEFAULT '',
    notes TEXT DEFAULT '',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id)
);

-- ============================================
-- NOTES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'progress',
    body TEXT DEFAULT '',
    is_finalized BOOLEAN DEFAULT FALSE,
    finalized_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id)
);

-- ============================================
-- ATTACHMENTS TABLE (metadata only, files in Storage)
-- ============================================
CREATE TABLE IF NOT EXISTS public.attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'other',
    filename TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size INTEGER DEFAULT 0,
    mime_type TEXT DEFAULT '',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id)
);

-- ============================================
-- VITALS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.vitals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    temp_c DOUBLE PRECISION,
    sbp INTEGER,
    dbp INTEGER,
    hr INTEGER,
    spo2 INTEGER,
    rr INTEGER,
    weight_kg DOUBLE PRECISION,
    height_cm DOUBLE PRECISION,
    head_circ_cm DOUBLE PRECISION,
    notes TEXT DEFAULT '',
    created_by UUID REFERENCES public.profiles(id)
);

-- ============================================
-- APPOINTMENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
    start_time TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER DEFAULT 15,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id)
);

-- ============================================
-- PHYSICIANS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.physicians (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    specialty TEXT DEFAULT '',
    clinic TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- REFERENCES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.references (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    category TEXT DEFAULT 'General',
    body TEXT DEFAULT '',
    is_favorite BOOLEAN DEFAULT FALSE,
    file_path TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.physicians ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.references ENABLE ROW LEVEL SECURITY;

-- Helper function to get current user's role
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- ============================================
-- PROFILES POLICIES
-- ============================================
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- ============================================
-- PATIENTS POLICIES
-- ============================================
-- Everyone can view patients
CREATE POLICY "All authenticated users can view patients"
    ON public.patients FOR SELECT
    TO authenticated
    USING (true);

-- Everyone can create patients
CREATE POLICY "All authenticated users can create patients"
    ON public.patients FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Physicians can update/delete any patient
-- Nurses/Secretaries can only update (not hard delete)
CREATE POLICY "Physicians can update patients"
    ON public.patients FOR UPDATE
    TO authenticated
    USING (true);

-- Only physicians can hard delete
CREATE POLICY "Only physicians can delete patients"
    ON public.patients FOR DELETE
    TO authenticated
    USING (public.get_user_role() = 'physician');

-- ============================================
-- NOTES POLICIES
-- ============================================
-- Everyone can view notes
CREATE POLICY "All authenticated users can view notes"
    ON public.notes FOR SELECT
    TO authenticated
    USING (true);

-- Only physicians can create/update/delete notes
CREATE POLICY "Only physicians can create notes"
    ON public.notes FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can update notes"
    ON public.notes FOR UPDATE
    TO authenticated
    USING (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can delete notes"
    ON public.notes FOR DELETE
    TO authenticated
    USING (public.get_user_role() = 'physician');

-- ============================================
-- ATTACHMENTS POLICIES
-- ============================================
-- Everyone can view attachments
CREATE POLICY "All authenticated users can view attachments"
    ON public.attachments FOR SELECT
    TO authenticated
    USING (true);

-- Only physicians can manage attachments
CREATE POLICY "Only physicians can create attachments"
    ON public.attachments FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can update attachments"
    ON public.attachments FOR UPDATE
    TO authenticated
    USING (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can delete attachments"
    ON public.attachments FOR DELETE
    TO authenticated
    USING (public.get_user_role() = 'physician');

-- ============================================
-- VITALS POLICIES
-- ============================================
-- Everyone can view vitals
CREATE POLICY "All authenticated users can view vitals"
    ON public.vitals FOR SELECT
    TO authenticated
    USING (true);

-- Physicians and Nurses can manage vitals
CREATE POLICY "Physicians and nurses can create vitals"
    ON public.vitals FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() IN ('physician', 'nurse'));

CREATE POLICY "Physicians and nurses can update vitals"
    ON public.vitals FOR UPDATE
    TO authenticated
    USING (public.get_user_role() IN ('physician', 'nurse'));

CREATE POLICY "Physicians and nurses can delete vitals"
    ON public.vitals FOR DELETE
    TO authenticated
    USING (public.get_user_role() IN ('physician', 'nurse'));

-- ============================================
-- APPOINTMENTS POLICIES
-- ============================================
-- Everyone can view appointments
CREATE POLICY "All authenticated users can view appointments"
    ON public.appointments FOR SELECT
    TO authenticated
    USING (true);

-- Physicians and Secretaries can manage appointments
CREATE POLICY "Physicians and secretaries can create appointments"
    ON public.appointments FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() IN ('physician', 'secretary'));

CREATE POLICY "Physicians and secretaries can update appointments"
    ON public.appointments FOR UPDATE
    TO authenticated
    USING (public.get_user_role() IN ('physician', 'secretary'));

CREATE POLICY "Physicians and secretaries can delete appointments"
    ON public.appointments FOR DELETE
    TO authenticated
    USING (public.get_user_role() IN ('physician', 'secretary'));

-- ============================================
-- PHYSICIANS POLICIES
-- ============================================
-- Everyone can view physicians
CREATE POLICY "All authenticated users can view physicians"
    ON public.physicians FOR SELECT
    TO authenticated
    USING (true);

-- Only physicians can manage physician records
CREATE POLICY "Only physicians can create physician records"
    ON public.physicians FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can update physician records"
    ON public.physicians FOR UPDATE
    TO authenticated
    USING (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can delete physician records"
    ON public.physicians FOR DELETE
    TO authenticated
    USING (public.get_user_role() = 'physician');

-- ============================================
-- REFERENCES POLICIES
-- ============================================
-- Everyone can view references
CREATE POLICY "All authenticated users can view references"
    ON public.references FOR SELECT
    TO authenticated
    USING (true);

-- Only physicians can manage references
CREATE POLICY "Only physicians can create references"
    ON public.references FOR INSERT
    TO authenticated
    WITH CHECK (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can update references"
    ON public.references FOR UPDATE
    TO authenticated
    USING (public.get_user_role() = 'physician');

CREATE POLICY "Only physicians can delete references"
    ON public.references FOR DELETE
    TO authenticated
    USING (public.get_user_role() = 'physician');

-- ============================================
-- TRIGGERS FOR updated_at
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_profiles
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER set_updated_at_patients
    BEFORE UPDATE ON public.patients
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER set_updated_at_notes
    BEFORE UPDATE ON public.notes
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER set_updated_at_references
    BEFORE UPDATE ON public.references
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- TRIGGER TO CREATE PROFILE ON SIGNUP
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'role', 'secretary')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- STORAGE BUCKET FOR ATTACHMENTS
-- ============================================
-- Run this in a separate query or via Supabase Dashboard → Storage
-- INSERT INTO storage.buckets (id, name, public) VALUES ('attachments', 'attachments', false);

-- Storage policies (run after creating bucket)
-- CREATE POLICY "Authenticated users can upload attachments"
--     ON storage.objects FOR INSERT
--     TO authenticated
--     WITH CHECK (bucket_id = 'attachments');

-- CREATE POLICY "Authenticated users can view attachments"
--     ON storage.objects FOR SELECT
--     TO authenticated
--     USING (bucket_id = 'attachments');

-- CREATE POLICY "Physicians can delete attachments"
--     ON storage.objects FOR DELETE
--     TO authenticated
--     USING (bucket_id = 'attachments' AND public.get_user_role() = 'physician');

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================
CREATE INDEX IF NOT EXISTS idx_patients_is_deleted ON public.patients(is_deleted);
CREATE INDEX IF NOT EXISTS idx_patients_created_at ON public.patients(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_patient_id ON public.notes(patient_id);
CREATE INDEX IF NOT EXISTS idx_notes_is_deleted ON public.notes(is_deleted);
CREATE INDEX IF NOT EXISTS idx_attachments_patient_id ON public.attachments(patient_id);
CREATE INDEX IF NOT EXISTS idx_vitals_patient_id ON public.vitals(patient_id);
CREATE INDEX IF NOT EXISTS idx_vitals_recorded_at ON public.vitals(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_appointments_start_time ON public.appointments(start_time);
CREATE INDEX IF NOT EXISTS idx_appointments_patient_id ON public.appointments(patient_id);

-- Done! Your database schema is ready.
