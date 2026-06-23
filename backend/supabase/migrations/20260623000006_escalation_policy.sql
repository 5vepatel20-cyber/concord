-- ALRT-06: Escalation policy + after-hours routing.
--
-- Each patient can define escalation policies that control how alerts are
-- routed based on severity, time of day, and target role.

create table if not exists public.escalation_policy (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  name text not null default 'Default',
  severity_threshold text not null default 'urgent'
    check (severity_threshold in ('info', 'urgent', 'emergency')),
  time_restriction text not null default 'always'
    check (time_restriction in ('always', 'business_hours', 'after_hours')),
  target_role text not null default 'caregiver'
    check (target_role in ('caregiver', 'clinician', 'both')),
  delay_minutes integer not null default 0 check (delay_minutes >= 0),
  notification_channel text not null default 'email'
    check (notification_channel in ('email', 'push', 'sms')),
  priority integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists escalation_policy_patient_idx
  on public.escalation_policy (patient_id);

-- Track acknowledgement on symptom_alert.
alter table public.symptom_alert
  add column if not exists acknowledged_by uuid references public."user"(id) on delete set null,
  add column if not exists acknowledged_at timestamptz;

-- RLS.
alter table public.escalation_policy enable row level security;

create policy "patient can manage own escalation policies"
  on public.escalation_policy
  for all
  using (patient_id = auth.uid())
  with check (patient_id = auth.uid());

create policy "caregivers can view escalation policies"
  on public.escalation_policy
  for select
  using (
    patient_id in (
      select patient_id from public.care_relationship
      where member_user_id = auth.uid() and status = 'active'
    )
  );
