-- SEC-06: Audit log for HIPAA-relevant data access and mutations.
-- Append-only log of patient data operations by authenticated users.
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public."user"(id) on delete cascade,
  actor_id uuid not null references public."user"(id) on delete cascade,
  action text not null,
  entity_type text,
  entity_id text,
  details jsonb,
  ip_address text,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_log_patient_id on public.audit_log(patient_id);
create index if not exists idx_audit_log_created_at on public.audit_log(created_at desc);

alter table public.audit_log enable row level security;

create policy "audit_log_select_own"
  on public.audit_log for select
  using (patient_id = auth.uid());

-- Service role bypasses RLS for inserts; this allows the backend to log.
create policy "audit_log_insert_service"
  on public.audit_log for insert
  with check (true);
