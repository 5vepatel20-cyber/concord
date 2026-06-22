-- Concord v0.2 — onboarding + consent tracking.
--
-- 1. Link oncology conditions to the chemo-core PRO-CTCAE panel so
--    condition selection automatically loads the right symptom terms.
-- 2. Add consent table for versioned, server-side consent records.
-- 3. Add RLS for the new table.

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Link oncology conditions → chemo-core panel                        ║
-- ╚════════════════════════════════════════════════════════════════════╝

do $$
declare
  panel_id uuid;
begin
  select id into panel_id from public.symptom_panel where name = 'Chemo core panel' limit 1;
  if panel_id is not null then
    update public.condition set pro_ctcae_panel_id = panel_id
      where category = 'oncology'
        and pro_ctcae_panel_id is null;
  end if;
end $$;

-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ Consent table                                                       ║
-- ╚════════════════════════════════════════════════════════════════════╝

-- Each row records one consent acceptance event. The latest row per user
-- is the "current" consent version.
create table if not exists public.user_consent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public."user"(id) on delete cascade,
  consent_version text not null,
  accepted_at timestamptz not null default now()
);

create index if not exists user_consent_user_idx
  on public.user_consent (user_id, accepted_at desc);

alter table public.user_consent enable row level security;

-- A patient can read and insert their own consent rows.
drop policy if exists user_consent_self_read on public.user_consent;
create policy user_consent_self_read on public.user_consent for select
  using (user_id = auth.uid());

drop policy if exists user_consent_self_insert on public.user_consent;
create policy user_consent_self_insert on public.user_consent for insert
  with check (user_id = auth.uid());
