-- ONB-02: Add regimen_name to patient_profile for onboarding diagnosis detail.
alter table if exists public.patient_profile
  add column if not exists regimen_name text;
