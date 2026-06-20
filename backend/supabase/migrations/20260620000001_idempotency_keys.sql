-- 20260620000001_idempotency_keys.sql
--
-- Idempotency-Key table for write endpoints (specifically /api/symptoms/submit).
-- The offline-queue in the Flutter app retries payloads that haven't been
-- acknowledged by the server. Without idempotency keys, a retry could
-- create a second symptom_report row when the first request actually
-- succeeded but the response was lost (e.g. network blip right after
-- the server writes, before the client receives 201).
--
-- Contract:
--   - POST /api/symptoms/submit accepts an optional `Idempotency-Key`
--     header (UUID recommended). When present, the server:
--       1. SELECTs from this table WHERE user_id = auth.uid() AND key = $1
--       2. If found: returns the stored response_body with status_code.
--       3. If not found: runs the write, then INSERTs (user_id, key,
--          response_body, status_code) on success.
--   - Keys are scoped to user_id so two patients can't collide.
--   - TTL is 24h. A scheduled cleanup deletes expired rows.

create table if not exists idempotency_keys (
  user_id       uuid        not null references auth.users (id) on delete cascade,
  key           text        not null,
  status_code   int         not null,
  response_body jsonb       not null,
  created_at    timestamptz not null default now(),
  primary key (user_id, key)
);

create index if not exists idempotency_keys_created_at_idx
  on idempotency_keys (created_at);

-- Optional scheduled cleanup. Supabase supports pg_cron via the dashboard;
-- if enabled, schedule: select cron.schedule('purge-idempotency', '0 3 * * *',
--   $$ delete from idempotency_keys where created_at < now() - interval '24 hours' $$);
-- The migration adds the function either way so it's available.
create or replace function purge_expired_idempotency_keys()
returns int
language plpgsql
security definer
as $$
declare
  deleted_count int;
begin
  delete from idempotency_keys
  where created_at < now() - interval '24 hours';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

comment on table idempotency_keys is
  'Caches HTTP responses keyed by Idempotency-Key + user, so write endpoints can be safely retried.';
comment on function purge_expired_idempotency_keys() is
  'Removes idempotency keys older than 24h. Schedule via pg_cron in production.';

-- RLS: a user can only see/insert their own rows. The server uses the
-- service role key (which bypasses RLS), but the policy is the safety
-- net if the anon key is ever accidentally used.
alter table idempotency_keys enable row level security;

do $$ begin
  create policy idempotency_keys_self_select
    on idempotency_keys for select
    using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy idempotency_keys_self_insert
    on idempotency_keys for insert
    with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;