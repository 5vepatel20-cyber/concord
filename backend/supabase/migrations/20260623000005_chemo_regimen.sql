-- MED-03: Chemo regimen templates — cyclical on/off schedules.
--
-- A regimen defines a repeating chemo protocol (e.g. "AC-T every 21 days")
-- with cycle_length_days (on-days) and rest_days (off-days between cycles).
-- Starting a regimen generates treatment_event rows for each cycle.

create table if not exists public.treatment_regimen (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  name text not null,
  description text,
  cycle_length_days integer not null check (cycle_length_days > 0),
  rest_days integer not null default 0 check (rest_days >= 0),
  total_cycles integer not null check (total_cycles > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists treatment_regimen_patient_idx
  on public.treatment_regimen (patient_id);

create table if not exists public.treatment_regimen_medication (
  id uuid primary key default gen_random_uuid(),
  regimen_id uuid not null references public.treatment_regimen(id) on delete cascade,
  medication_name text not null,
  rxnorm_cui text,
  dose text,
  unit text,
  route text,
  day_within_cycle integer not null default 1 check (day_within_cycle > 0),
  notes text
);

create index if not exists treatment_regimen_medication_regimen_idx
  on public.treatment_regimen_medication (regimen_id);

-- Link treatment_event back to its originating regimen.
alter table public.treatment_event
  add column if not exists regimen_id uuid references public.treatment_regimen(id) on delete set null,
  add column if not exists cycle_number integer;

-- RLS for regimens.
alter table public.treatment_regimen enable row level security;
alter table public.treatment_regimen_medication enable row level security;

create policy "patient can manage own regimens"
  on public.treatment_regimen
  for all
  using (patient_id = auth.uid())
  with check (patient_id = auth.uid());

create policy "caregivers can view regimens"
  on public.treatment_regimen
  for select
  using (
    patient_id in (
      select patient_id from public.care_relationship
      where member_user_id = auth.uid() and status = 'active'
    )
  );

create policy "regimen meds follow regimen"
  on public.treatment_regimen_medication
  for all
  using (
    regimen_id in (
      select id from public.treatment_regimen
      where patient_id = auth.uid()
    )
  )
  with check (
    regimen_id in (
      select id from public.treatment_regimen
      where patient_id = auth.uid()
    )
  );
