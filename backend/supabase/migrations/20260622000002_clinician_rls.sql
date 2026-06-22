-- Concord v0.3 — clinician RLS policies for the CLIN web app (Phase 2).
--
-- Clinicians need read access across all patient data in their panel.
-- This migration adds policy functions and policies for the `clinician` role.

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Helper: is the current user a clinician?                          ║
-- ╚════════════════════════════════════════════════════════════════════╝

create or replace function public.is_clinician()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public."user"
    where id = auth.uid()
      and role in ('clinician', 'admin')
  );
$$;

revoke all on function public.is_clinician() from public;
grant execute on function public.is_clinician() to authenticated;

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Clinician read policies across patient data tables                 ║
-- ╚════════════════════════════════════════════════════════════════════╝

-- We add a "clinician can read all" OR to existing RLS policies.
-- The existing policies are patient self + caregiver; this adds clinician.

do $$
declare
  tables_with_patient_id text[] := array[
    'patient_profile', 'symptom_report', 'symptom_alert',
    'medication', 'medication_event', 'task', 'health_metric_sample',
    'document', 'report', 'trial_match'
  ];
  t text;
begin
  -- user table: clinicians can read any user row.
  drop policy if exists user_clinician_read on public."user";
  create policy user_clinician_read on public."user" for select
    using (public.is_clinician());

  -- patient_profile
  drop policy if exists patient_profile_clinician_read on public.patient_profile;
  create policy patient_profile_clinician_read on public.patient_profile for select
    using (public.is_clinician());

  -- condition, symptom_term, symptom_panel, alert_rule already readable
  -- by all authenticated users, so clinicians already have access.

  foreach t in array tables_with_patient_id loop
    execute format($$
      drop policy if exists %I_clinician_read on public.%I;
      create policy %I_clinician_read on public.%I for select
        using (public.is_clinician());
    $$, t, t, t, t);
  end loop;

  -- symptom_alert: clinicians can also write (ack/resolve).
  drop policy if exists symptom_alert_clinician_write on public.symptom_alert;
  create policy symptom_alert_clinician_write on public.symptom_alert for update
    using (public.is_clinician())
    with check (public.is_clinician());
end $$;
