-- CARE-04: Multi-caregiver task coordination.
-- Adds assigned_to column so tasks can be delegated to specific care team members.

alter table public.task
  add column assigned_to uuid references public."user"(id) on delete set null;

create index if not exists task_assigned_to_idx
  on public.task (assigned_to);

-- Update RLS on task: patient sees all their tasks; assigned caregiver sees theirs.
drop policy if exists task_patient_access on public.task;

create policy task_patient_access on public.task
  for all
  using (
    patient_id = auth.uid()
    or assigned_to = auth.uid()
    or (assigned_to is null and public.is_active_caregiver_for(patient_id))
  );
