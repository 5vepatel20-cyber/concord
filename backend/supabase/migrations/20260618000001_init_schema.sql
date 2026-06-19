-- Concord v0.1 — initial schema.
-- Tables: user-extensions, condition, care_relationship, PRO-CTCAE core
-- (term/panel/report/response/alert/rule), medications, tasks, health metrics,
-- documents, reports, trials.
-- Plus: RLS policies, the chem-core panel + term seed.
-- All pgvector/embedding infrastructure deferred to Phase 2 (AI-07).

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Extensions                                                         ║
-- ╚════════════════════════════════════════════════════════════════════╝

create extension if not exists "pgcrypto";

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Enums                                                              ║
-- ╚════════════════════════════════════════════════════════════════════╝

do $$ begin
  create type user_role as enum ('patient', 'caregiver', 'clinician', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type condition_category as enum
    ('oncology', 'cardiometabolic', 'autoimmune', 'respiratory', 'mental_health', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type treatment_status as enum
    ('active_treatment', 'surveillance', 'remission', 'palliative');
exception when duplicate_object then null; end $$;

do $$ begin
  create type relationship_kind as enum
    ('spouse', 'child', 'parent', 'friend', 'clinician', 'care_navigator');
exception when duplicate_object then null; end $$;

do $$ begin
  create type care_status as enum ('pending', 'active', 'revoked');
exception when duplicate_object then null; end $$;

do $$ begin
  create type recall_window as enum ('now', 'past_7_days');
exception when duplicate_object then null; end $$;

do $$ begin
  create type report_source as enum ('self', 'caregiver', 'voice');
exception when duplicate_object then null; end $$;

do $$ begin
  create type alert_severity as enum ('info', 'urgent', 'emergency');
exception when duplicate_object then null; end $$;

do $$ begin
  create type alert_status as enum ('open', 'acknowledged', 'resolved');
exception when duplicate_object then null; end $$;

do $$ begin
  create type med_route as enum ('oral', 'iv', 'sub_q', 'topical', 'inhaled', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type med_source as enum ('manual', 'healthkit', 'document_extracted', 'clinician');
exception when duplicate_object then null; end $$;

do $$ begin
  create type med_event_status as enum ('taken', 'skipped', 'missed', 'taken_late');
exception when duplicate_object then null; end $$;

do $$ begin
  create type task_category as enum ('appointment', 'measurement', 'lifestyle', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type task_source as enum ('manual', 'ai_proposed', 'clinician');
exception when duplicate_object then null; end $$;

do $$ begin
  create type health_metric_type as enum
    ('steps', 'sleep', 'hr', 'bp_sys', 'bp_dia', 'glucose', 'calories', 'weight');
exception when duplicate_object then null; end $$;

do $$ begin
  create type health_source as enum ('healthkit', 'manual', 'device');
exception when duplicate_object then null; end $$;

do $$ begin
  create type document_kind as enum
    ('discharge_summary', 'lab_result', 'imaging', 'visit_note', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type report_kind as enum
    ('visit_prep', 'interval_summary', 'shared_with_clinician');
exception when duplicate_object then null; end $$;

do $$ begin
  create type trial_status as enum ('suggested', 'saved', 'contacted', 'dismissed');
exception when duplicate_object then null; end $$;

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Identity & profile                                                  ║
-- ╚════════════════════════════════════════════════════════════════════╝

-- Extensions to Supabase auth.users. We keep auth.users as the source of
-- truth for auth (email, password, sessions) and add our own public.user
-- row for app-level profile data (DOB, role, locale).
create table if not exists public."user" (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  date_of_birth date,
  sex_at_birth text,
  locale text not null default 'en',
  role user_role not null default 'patient',
  created_at timestamptz not null default now()
);

create index if not exists user_role_idx on public."user" (role);

-- A patient profile is a 1:1 extension of user for clinical context.
create table if not exists public.patient_profile (
  user_id uuid primary key references public."user"(id) on delete cascade,
  primary_diagnosis_id uuid, -- FK added after condition table
  diagnosis_date date,
  cancer_stage text,
  treatment_status treatment_status,
  height_cm numeric(5,1),
  weight_kg numeric(5,1),
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now()
);

-- Controlled vocabulary for conditions (EOM cancer types + common chronic).
create table if not exists public.condition (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  icd10_code text,
  category condition_category not null,
  pro_ctcae_panel_id uuid, -- FK added after symptom_panel
  created_at timestamptz not null default now()
);

create index if not exists condition_category_idx on public.condition (category);

-- Care relationships (caregiver, clinician, navigator).
create table if not exists public.care_relationship (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  member_user_id uuid not null references public."user"(id) on delete cascade,
  relationship relationship_kind not null,
  permissions jsonb not null default '{}'::jsonb,
  status care_status not null default 'pending',
  created_at timestamptz not null default now(),
  unique (patient_id, member_user_id)
);

create index if not exists care_rel_patient_idx on public.care_relationship (patient_id);
create index if not exists care_rel_member_idx on public.care_relationship (member_user_id);

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ PRO-CTCAE core                                                      ║
-- ╚════════════════════════════════════════════════════════════════════╝

create table if not exists public.symptom_term (
  id uuid primary key default gen_random_uuid(),
  pro_ctcae_code text not null unique,
  display_name text not null,
  body_system text not null,
  attributes text[] not null,
  plain_language text,
  created_at timestamptz not null default now()
);

create table if not exists public.symptom_panel (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  term_ids uuid[] not null default '{}'::uuid[],
  created_at timestamptz not null default now()
);

create table if not exists public.symptom_report (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  reported_at timestamptz not null default now(),
  recall_window recall_window not null default 'now',
  source report_source not null default 'self',
  free_text text,
  audio_url text,
  created_at timestamptz not null default now()
);

create index if not exists symptom_report_patient_time_idx
  on public.symptom_report (patient_id, reported_at desc);

create table if not exists public.symptom_response (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.symptom_report(id) on delete cascade,
  term_id uuid not null references public.symptom_term(id) on delete restrict,
  frequency smallint,
  severity smallint,
  interference smallint,
  presence boolean,
  amount smallint,
  composite_grade smallint not null check (composite_grade between 0 and 3),
  body_location text,
  created_at timestamptz not null default now(),
  constraint symptom_response_attr_range check (
    (frequency is null or frequency between 0 and 4)
    and (severity is null or severity between 0 and 4)
    and (interference is null or interference between 0 and 4)
    and (amount is null or amount between 0 and 4)
  )
);

create index if not exists symptom_response_report_idx
  on public.symptom_response (report_id);
create index if not exists symptom_response_term_grade_idx
  on public.symptom_response (term_id, composite_grade);

create table if not exists public.alert_rule (
  id uuid primary key default gen_random_uuid(),
  term_id uuid references public.symptom_term(id) on delete cascade,
  condition jsonb not null,
  severity_level alert_severity not null,
  escalation jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.symptom_alert (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  report_id uuid references public.symptom_report(id) on delete set null,
  rule_id uuid references public.alert_rule(id) on delete set null,
  severity_level alert_severity not null,
  status alert_status not null default 'open',
  acknowledged_by uuid references public."user"(id) on delete set null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists symptom_alert_patient_status_idx
  on public.symptom_alert (patient_id, status, created_at desc);

-- Now wire the two circular FKs we deferred.
alter table public.patient_profile
  drop constraint if exists patient_profile_primary_diagnosis_id_fkey;
alter table public.patient_profile
  add constraint patient_profile_primary_diagnosis_id_fkey
  foreign key (primary_diagnosis_id) references public.condition(id) on delete set null;

alter table public.condition
  drop constraint if exists condition_pro_ctcae_panel_id_fkey;
alter table public.condition
  add constraint condition_pro_ctcae_panel_id_fkey
  foreign key (pro_ctcae_panel_id) references public.symptom_panel(id) on delete set null;

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Medications & adherence                                             ║
-- ╚════════════════════════════════════════════════════════════════════╝

create table if not exists public.medication (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  rxnorm_code text,
  display_name text not null,
  dose text,
  unit text,
  route med_route not null default 'oral',
  schedule jsonb not null default '{}'::jsonb,
  source med_source not null default 'manual',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists medication_patient_active_idx
  on public.medication (patient_id, active);

create table if not exists public.medication_event (
  id uuid primary key default gen_random_uuid(),
  medication_id uuid not null references public.medication(id) on delete cascade,
  scheduled_for timestamptz not null,
  status med_event_status not null,
  logged_at timestamptz not null default now()
);

create index if not exists medication_event_med_time_idx
  on public.medication_event (medication_id, scheduled_for desc);

create table if not exists public.task (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  title text not null,
  due_at timestamptz,
  category task_category not null default 'admin',
  status text not null default 'open',
  source task_source not null default 'manual',
  created_at timestamptz not null default now()
);

create index if not exists task_patient_due_idx
  on public.task (patient_id, due_at);

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Health metrics                                                      ║
-- ╚════════════════════════════════════════════════════════════════════╝

create table if not exists public.health_metric_sample (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  type health_metric_type not null,
  value numeric,
  unit text,
  measured_at timestamptz not null,
  source health_source not null default 'healthkit',
  created_at timestamptz not null default now()
);

create index if not exists health_metric_patient_type_time_idx
  on public.health_metric_sample (patient_id, type, measured_at desc);

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Documents & reports                                                 ║
-- ╚════════════════════════════════════════════════════════════════════╝

create table if not exists public.document (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  kind document_kind not null default 'other',
  storage_url text not null,
  ocr_text text,
  ai_plain_summary text,
  extracted_values jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists document_patient_idx
  on public.document (patient_id, created_at desc);

create table if not exists public.report (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  kind report_kind not null default 'interval_summary',
  date_range daterange,
  structured_payload jsonb not null default '{}'::jsonb,
  narrative text,
  pdf_url text,
  shared_with uuid[] not null default '{}'::uuid[],
  created_at timestamptz not null default now()
);

create index if not exists report_patient_idx
  on public.report (patient_id, created_at desc);

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Clinical trials                                                      ║
-- ╚════════════════════════════════════════════════════════════════════╝

create table if not exists public.trial_match (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  nct_id text not null,
  match_score numeric(4,3),
  status trial_status not null default 'suggested',
  created_at timestamptz not null default now(),
  unique (patient_id, nct_id)
);

create index if not exists trial_match_patient_status_idx
  on public.trial_match (patient_id, status);

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Triggers: keep public.user in sync with auth.users                   ║
-- ╚════════════════════════════════════════════════════════════════════╝

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public."user" (id, email, full_name, locale)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'locale', 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Row-Level Security                                                  ║
-- ╚════════════════════════════════════════════════════════════════════╝

-- RLS rule of thumb: a patient sees their own rows; a caregiver sees rows
-- for patients they're actively linked to; a clinician sees rows for
-- patients on their panel. Today we implement the first two; the
-- clinician panel comes in Phase 2.

alter table public."user" enable row level security;
alter table public.patient_profile enable row level security;
alter table public.condition enable row level security;
alter table public.care_relationship enable row level security;
alter table public.symptom_term enable row level security;
alter table public.symptom_panel enable row level security;
alter table public.symptom_report enable row level security;
alter table public.symptom_response enable row level security;
alter table public.alert_rule enable row level security;
alter table public.symptom_alert enable row level security;
alter table public.medication enable row level security;
alter table public.medication_event enable row level security;
alter table public.task enable row level security;
alter table public.health_metric_sample enable row level security;
alter table public.document enable row level security;
alter table public.report enable row level security;
alter table public.trial_match enable row level security;

-- Helper: is the current user an active caregiver for this patient?
create or replace function public.is_active_caregiver_for(p_patient uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.care_relationship
    where patient_id = p_patient
      and member_user_id = auth.uid()
      and status = 'active'
  );
$$;

revoke all on function public.is_active_caregiver_for(uuid) from public;
grant execute on function public.is_active_caregiver_for(uuid) to authenticated;

-- user: a user can read/update their own row; an active caregiver can read.
drop policy if exists user_self_read on public."user";
create policy user_self_read on public."user" for select
  using (id = auth.uid() or public.is_active_caregiver_for(id));

drop policy if exists user_self_update on public."user";
create policy user_self_update on public."user" for update
  using (id = auth.uid()) with check (id = auth.uid());

-- patient_profile: same as user.
drop policy if exists patient_profile_self_read on public.patient_profile;
create policy patient_profile_self_read on public.patient_profile for select
  using (user_id = auth.uid() or public.is_active_caregiver_for(user_id));

drop policy if exists patient_profile_self_write on public.patient_profile;
create policy patient_profile_self_write on public.patient_profile for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- care_relationship: a user sees rows where they are patient OR member.
drop policy if exists care_relationship_party_read on public.care_relationship;
create policy care_relationship_party_read on public.care_relationship for select
  using (patient_id = auth.uid() or member_user_id = auth.uid());

drop policy if exists care_relationship_patient_write on public.care_relationship;
create policy care_relationship_patient_write on public.care_relationship for all
  using (patient_id = auth.uid()) with check (patient_id = auth.uid());

-- condition, symptom_term, symptom_panel, alert_rule: readable by all
-- authenticated users (shared vocabularies). Writable only by service_role
-- (the backend manages these).
drop policy if exists condition_read_all on public.condition;
create policy condition_read_all on public.condition for select
  using (auth.uid() is not null);

drop policy if exists symptom_term_read_all on public.symptom_term;
create policy symptom_term_read_all on public.symptom_term for select
  using (auth.uid() is not null);

drop policy if exists symptom_panel_read_all on public.symptom_panel;
create policy symptom_panel_read_all on public.symptom_panel for select
  using (auth.uid() is not null);

drop policy if exists alert_rule_read_all on public.alert_rule;
create policy alert_rule_read_all on public.alert_rule for select
  using (auth.uid() is not null);

-- symptom_report: patient + their caregivers.
drop policy if exists symptom_report_party_read on public.symptom_report;
create policy symptom_report_party_read on public.symptom_report for select
  using (patient_id = auth.uid() or public.is_active_caregiver_for(patient_id));

drop policy if exists symptom_report_self_write on public.symptom_report;
create policy symptom_report_self_write on public.symptom_report for all
  using (patient_id = auth.uid()) with check (patient_id = auth.uid());

-- symptom_response: same as its parent report.
drop policy if exists symptom_response_via_report on public.symptom_response;
create policy symptom_response_via_report on public.symptom_response for all
  using (
    exists (
      select 1 from public.symptom_report r
      where r.id = symptom_response.report_id
        and (r.patient_id = auth.uid() or public.is_active_caregiver_for(r.patient_id))
    )
  ) with check (
    exists (
      select 1 from public.symptom_report r
      where r.id = symptom_response.report_id
        and r.patient_id = auth.uid()
    )
  );

-- symptom_alert: patient + caregiver read; service_role writes.
drop policy if exists symptom_alert_party_read on public.symptom_alert;
create policy symptom_alert_party_read on public.symptom_alert for select
  using (patient_id = auth.uid() or public.is_active_caregiver_for(patient_id));

-- medication, medication_event, task, health_metric_sample, document,
-- report, trial_match: same patient+caregiver pattern as symptom_report.
do $$
declare t text;
begin
  for t in select unnest(array[
    'medication', 'medication_event', 'task', 'health_metric_sample',
    'document', 'report', 'trial_match'
  ]) loop
    execute format($$
      drop policy if exists %I_party_read on public.%I;
      create policy %I_party_read on public.%I for select
        using (patient_id = auth.uid() or public.is_active_caregiver_for(patient_id));
    $$, t, t, t, t);

    if t <> 'medication_event' then
      execute format($$
        drop policy if exists %I_self_write on public.%I;
        create policy %I_self_write on public.%I for all
          using (patient_id = auth.uid()) with check (patient_id = auth.uid());
      $$, t, t, t, t);
    end if;
  end loop;
end $$;

-- medication_event: keyed by medication, not patient. Reuse the medication's
-- patient_id.
drop policy if exists medication_event_via_med on public.medication_event;
create policy medication_event_via_med on public.medication_event for all
  using (
    exists (
      select 1 from public.medication m
      where m.id = medication_event.medication_id
        and (m.patient_id = auth.uid() or public.is_active_caregiver_for(m.patient_id))
    )
  ) with check (
    exists (
      select 1 from public.medication m
      where m.id = medication_event.medication_id
        and m.patient_id = auth.uid()
    )
  );

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Seed: chem-core panel + 22 starter PRO-CTCAE terms + 7 EOM oncology  ║
-- ║ conditions                                                          ║
-- ╚════════════════════════════════════════════════════════════════════╝

insert into public.symptom_term (pro_ctcae_code, display_name, body_system, attributes, plain_language) values
  ('G1',  'Nausea',                          'GI',           array['frequency','severity'],                          'Feeling like you might throw up'),
  ('G2',  'Vomiting',                        'GI',           array['frequency','severity'],                          'Throwing up'),
  ('G3',  'Diarrhea',                        'GI',           array['frequency'],                                     'Loose or watery stools'),
  ('G4',  'Constipation',                    'GI',           array['severity'],                                      'Hard time pooping'),
  ('G5',  'Decreased appetite',              'GI',           array['severity'],                                      'Not feeling hungry'),
  ('G6',  'Mouth/throat sores',              'GI',           array['severity'],                                      'Painful spots in mouth or throat'),
  ('G7',  'Taste changes',                   'GI',           array['severity'],                                      'Food tastes different or has no taste'),
  ('C1',  'Fatigue',                         'constitutional',array['severity','interference'],                      'Feeling very tired'),
  ('C2',  'Fever',                           'constitutional',array['presence'],                                      'Temperature of 100.4F (38C) or higher'),
  ('C3',  'Chills',                          'constitutional',array['severity'],                                      'Shivering or feeling cold'),
  ('C4',  'Night sweats',                    'constitutional',array['frequency','severity'],                          'Heavy sweating at night'),
  ('C5',  'Weight loss',                     'constitutional',array['amount'],                                        'Losing weight without trying'),
  ('P1',  'General pain',                    'pain',         array['frequency','severity','interference'],           'Aches or pain anywhere in the body'),
  ('P2',  'Headache',                        'pain',         array['frequency','severity','interference'],           'Pain in the head'),
  ('P3',  'Abdominal pain',                  'pain',         array['frequency','severity','interference'],           'Pain in the belly'),
  ('N1',  'Numbness/tingling in hands/feet', 'neuro',        array['severity','interference'],                      'Pins-and-needles or numbness in hands or feet'),
  ('D1',  'Rash',                            'derm',         array['presence'],                                      'New rash or skin change'),
  ('D2',  'Skin dryness',                    'derm',         array['severity'],                                      'Very dry or peeling skin'),
  ('D3',  'Hair loss',                       'derm',         array['amount'],                                        'Losing more hair than usual'),
  ('PS1', 'Anxiety',                         'psych',        array['frequency','severity','interference'],           'Feeling worried, on edge, or panicky'),
  ('PS2', 'Sadness',                         'psych',        array['frequency','severity','interference'],           'Feeling down or hopeless'),
  ('PS3', 'Trouble sleeping',                'psych',        array['severity','interference'],                      'Hard time falling or staying asleep')
on conflict (pro_ctcae_code) do nothing;

-- Build the chem-core panel from all seeded terms.
do $$
declare
  panel_id uuid;
  term_id uuid;
begin
  insert into public.symptom_panel (name) values ('Chemo core panel')
    on conflict do nothing
    returning id into panel_id;

  if panel_id is null then
    select id into panel_id from public.symptom_panel where name = 'Chemo core panel' limit 1;
  end if;

  update public.symptom_panel
    set term_ids = coalesce(term_ids, '{}'::uuid[]) || (
      select coalesce(array_agg(id), '{}'::uuid[]) from public.symptom_term
    )
    where id = panel_id
      and (term_ids is null or cardinality(term_ids) = 0);
end $$;

-- Seed the 7 EOM cancer types + a couple of common chronic conditions.
insert into public.condition (display_name, icd10_code, category) values
  ('Breast cancer',                     'C50',   'oncology'),
  ('Chronic leukemia',                  'C91',   'oncology'),
  ('Small intestine / colorectal cancer','C17/C18-C20','oncology'),
  ('Lung cancer',                       'C34',   'oncology'),
  ('Lymphoma',                          'C81-C86','oncology'),
  ('Multiple myeloma',                  'C90',   'oncology'),
  ('Prostate cancer',                   'C61',   'oncology'),
  ('Heart failure',                     'I50',   'cardiometabolic'),
  ('Type 2 diabetes',                   'E11',   'cardiometabolic'),
  ('Rheumatoid arthritis',              'M06',   'autoimmune'),
  ('COPD',                              'J44',   'respiratory'),
  ('Major depressive disorder',         'F33',   'mental_health')
on conflict do nothing;
