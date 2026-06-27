-- Waitlist for early access to symptom tracking.
-- Captures emails from the landing page EmailCapture component
-- (viral funnel: anonymous decode user -> waitlist -> convert).
-- RLS is NOT needed here because the backend service_role handles
-- all inserts (public endpoint, no user session). We disable RLS.

create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'landing',
  referred_from text,
  created_at timestamptz not null default now()
);

create unique index if not exists waitlist_email_idx on public.waitlist (lower(email));

-- Disable RLS — this is entirely service_role managed.
alter table public.waitlist disable row level security;
