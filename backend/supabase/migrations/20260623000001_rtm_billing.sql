-- RTM billing infrastructure (CLIN-05).
-- Tracks enrollment, monthly periods, and time entries for CPT codes
-- 98975 (setup), 98980 (first 20 min), 98981 (additional 20 min).

do $$ begin
  create type rtm_enrollment_status as enum ('active', 'paused', 'discontinued');
exception when duplicate_object then null; end $$;

do $$ begin
  create type rtm_cpt_code as enum ('98975', '98980', '98981');
exception when duplicate_object then null; end $$;

create table if not exists public.rtm_enrollment (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  status rtm_enrollment_status not null default 'active',
  enrolled_at timestamptz not null default now(),
  cpt_98975_billed boolean not null default false,
  consent_on_file boolean not null default false,
  created_at timestamptz not null default now(),
  unique (patient_id)
);

create index if not exists rtm_enrollment_status_idx
  on public.rtm_enrollment (status);

create table if not exists public.rtm_billing_period (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  year smallint not null,
  month smallint not null check (month between 1 and 12),
  total_minutes int not null default 0 check (total_minutes >= 0),
  cpt_98980_units smallint not null default 0,
  cpt_98981_units smallint not null default 0,
  billed boolean not null default false,
  billed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (patient_id, year, month)
);

create index if not exists rtm_billing_period_patient_idx
  on public.rtm_billing_period (patient_id, year desc, month desc);
create index if not exists rtm_billing_period_month_idx
  on public.rtm_billing_period (year, month);

create table if not exists public.rtm_time_entry (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  clinician_id uuid not null references public."user"(id) on delete cascade,
  billing_period_id uuid references public.rtm_billing_period(id) on delete set null,
  cpt_code rtm_cpt_code not null,
  minutes smallint not null check (minutes > 0 and minutes <= 120),
  description text,
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists rtm_time_entry_period_idx
  on public.rtm_time_entry (billing_period_id);
create index if not exists rtm_time_entry_patient_idx
  on public.rtm_time_entry (patient_id, logged_at desc);

-- Automatically update rtm_billing_period.total_minutes when entries are added.
create or replace function public.recalc_rtm_period_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  yr smallint;
  mo smallint;
begin
  if tg_op = 'delete' then
    pid := old.patient_id;
    yr := extract(year from old.logged_at)::smallint;
    mo := extract(month from old.logged_at)::smallint;
  else
    pid := new.patient_id;
    yr := extract(year from new.logged_at)::smallint;
    mo := extract(month from new.logged_at)::smallint;
  end if;

  insert into public.rtm_billing_period (patient_id, year, month)
  values (pid, yr, mo)
  on conflict (patient_id, year, month) do nothing;

  update public.rtm_billing_period
  set
    total_minutes = (
      select coalesce(sum(minutes), 0)
      from public.rtm_time_entry
      where patient_id = pid
        and extract(year from logged_at) = yr
        and extract(month from logged_at) = mo
    ),
    cpt_98980_units = (
      select count(*)::smallint
      from public.rtm_time_entry
      where patient_id = pid
        and cpt_code = '98980'
        and extract(year from logged_at) = yr
        and extract(month from logged_at) = mo
    ),
    cpt_98981_units = (
      select count(*)::smallint
      from public.rtm_time_entry
      where patient_id = pid
        and cpt_code = '98981'
        and extract(year from logged_at) = yr
        and extract(month from logged_at) = mo
    )
  where patient_id = pid and year = yr and month = mo;

  return coalesce(new, old);
end;
$$;

drop trigger if exists rtm_time_entry_aiu on public.rtm_time_entry;
create trigger rtm_time_entry_aiu
  after insert or update or delete on public.rtm_time_entry
  for each row execute function public.recalc_rtm_period_totals();

-- RLS
alter table public.rtm_enrollment enable row level security;
alter table public.rtm_billing_period enable row level security;
alter table public.rtm_time_entry enable row level security;

-- Clinicians and admins can read/write RTM data for all patients.
drop policy if exists rtm_enrollment_clinician_all on public.rtm_enrollment;
create policy rtm_enrollment_clinician_all on public.rtm_enrollment for all
  using (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  )
  with check (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  );

drop policy if exists rtm_billing_period_clinician_all on public.rtm_billing_period;
create policy rtm_billing_period_clinician_all on public.rtm_billing_period for all
  using (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  )
  with check (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  );

drop policy if exists rtm_time_entry_clinician_all on public.rtm_time_entry;
create policy rtm_time_entry_clinician_all on public.rtm_time_entry for all
  using (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  )
  with check (
    exists (select 1 from public."user" where id = auth.uid() and role in ('clinician', 'admin'))
  );
