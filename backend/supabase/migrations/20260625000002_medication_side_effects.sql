-- MED-07: Add side-effects-to-watch column to medication table.
alter table public.medication
  add column if not exists side_effects_watch text;
