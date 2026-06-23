-- CLIN-07: Secure messaging between patients and care team.
--
-- 1:1 conversations (patient <-> caregiver or patient <-> clinician).
-- Messages are insert-only; no edits or deletes for audit integrity.

create table if not exists public.conversation (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_participant (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversation(id) on delete cascade,
  user_id uuid not null references public."user"(id) on delete cascade,
  last_read_at timestamptz,
  unique (conversation_id, user_id)
);

create index if not exists conv_participant_user_idx
  on public.conversation_participant (user_id, last_read_at desc);

create table if not exists public.message (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversation(id) on delete cascade,
  sender_id uuid not null references public."user"(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists message_conversation_idx
  on public.message (conversation_id, created_at asc);

-- RLS.
alter table public.conversation enable row level security;
alter table public.conversation_participant enable row level security;
alter table public.message enable row level security;

-- Participants can see their conversations.
drop policy if exists conversation_participant_read on public.conversation;
create policy conversation_participant_read on public.conversation
  for select using (
    id in (
      select conversation_id from public.conversation_participant
      where user_id = auth.uid()
    )
  );

-- Participants can manage their own participant rows (for last_read_at).
drop policy if exists participant_self_read on public.conversation_participant;
create policy participant_self_read on public.conversation_participant
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Participants can read messages in their conversations.
drop policy if exists message_participant_read on public.message;
create policy message_participant_read on public.message
  for select using (
    conversation_id in (
      select conversation_id from public.conversation_participant
      where user_id = auth.uid()
    )
  );

-- Participants can insert messages in their conversations.
drop policy if exists message_participant_insert on public.message;
create policy message_participant_insert on public.message
  for insert with check (
    sender_id = auth.uid()
    and conversation_id in (
      select conversation_id from public.conversation_participant
      where user_id = auth.uid()
    )
  );
