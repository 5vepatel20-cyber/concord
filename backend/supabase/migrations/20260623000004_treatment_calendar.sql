-- ONB-05: Treatment calendar — appointments, chemo sessions, and key dates.
--
-- Each event represents a single treatment-related day (infusion, appointment,
-- lab draw, etc.). Patients see these in a calendar/timeline view.

create table if not exists public.treatment_event (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  event_type text not null check (
    event_type in ('infusion', 'appointment', 'lab', 'scan', 'surgery', 'other')
  ),
  title text not null,
  description text,
  location text,
  event_date date not null,
  event_time time,
  end_date date,                    -- optional range for multi-day events
  status text not null default 'scheduled' check (
    status in ('scheduled', 'completed', 'cancelled', 'rescheduled')
  ),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists treatment_event_patient_date_idx
  on public.treatment_event (patient_id, event_date desc);

-- Row-level security.
alter table public.treatment_event enable row level security;

create policy "patient can manage own events"
  on public.treatment_event
  for all
  using (patient_id = auth.uid())
  with check (patient_id = auth.uid());

create policy "caregivers can view events"
  on public.treatment_event
  for select
  using (
    patient_id in (
      select patient_id from public.care_relationship
      where member_user_id = auth.uid() and status = 'active'
    )
  );
