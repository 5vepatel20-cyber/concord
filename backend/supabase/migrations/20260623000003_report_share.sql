-- RPT-06: Share-to-clinician via secure expiring links.
--
-- Each row represents one share action against a generated report.
-- The token is a UUID used as a secret URL parameter — unguessable
-- and unique. When the link expires the token is still valid for
-- lookups but the API returns 410 Gone.

create table if not exists public.report_share_link (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.report(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  last_accessed_at timestamptz,
  access_count int not null default 0
);

create index if not exists report_share_link_token_idx
  on public.report_share_link (token);

create index if not exists report_share_link_report_idx
  on public.report_share_link (report_id);

-- Row-level security: the patient who owns the report can insert/select.
alter table public.report_share_link enable row level security;

create policy "patient can manage share links"
  on public.report_share_link
  for all
  using (
    report_id in (
      select id from public.report where patient_id = auth.uid()
    )
  )
  with check (
    report_id in (
      select id from public.report where patient_id = auth.uid()
    )
  );
