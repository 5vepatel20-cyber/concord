-- ALRT-02: Seed default oncology alert rules.
-- Idempotent: each rule is checked via a helper before insert.

do $$
declare
  tid uuid;
  rid uuid;
begin
  -- Emergency: severe nausea (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'G1';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'emergency', '{"notify_patient":true,"route":"inbox+push"}'::jsonb);
  end if;

  -- Emergency: severe vomiting (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'G2';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'emergency', '{"notify_patient":true,"route":"inbox+push"}'::jsonb);
  end if;

  -- Emergency: severe diarrhea (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'G3';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'emergency', '{"notify_patient":true,"route":"inbox+push"}'::jsonb);
  end if;

  -- Emergency: fever — febrile neutropenia concern
  select id into tid from public.symptom_term where pro_ctcae_code = 'C2';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"presence":true}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":1,"presence":true}'::jsonb, 'emergency', '{"notify_patient":true,"route":"inbox+push"}'::jsonb);
  end if;

  -- Urgent: severe general pain (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'P1';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'urgent', '{"notify_patient":true,"route":"inbox"}'::jsonb);
  end if;

  -- Urgent: severe headache (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'P2';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'urgent', '{"notify_patient":true,"route":"inbox"}'::jsonb);
  end if;

  -- Urgent: severe abdominal pain (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'P3';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'urgent', '{"notify_patient":true,"route":"inbox"}'::jsonb);
  end if;

  -- Urgent: severe numbness/tingling (grade 3) — possible CIPN
  select id into tid from public.symptom_term where pro_ctcae_code = 'N1';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'urgent', '{"route":"inbox"}'::jsonb);
  end if;

  -- Urgent: severe anxiety (grade 3)
  select id into tid from public.symptom_term where pro_ctcae_code = 'PS1';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":3}'::jsonb, 'urgent', '{"route":"inbox"}'::jsonb);
  end if;

  -- Info: moderate fatigue (grade 2)
  select id into tid from public.symptom_term where pro_ctcae_code = 'C1';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":2}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":2}'::jsonb, 'info', '{"route":"inbox"}'::jsonb);
  end if;

  -- Info: mouth/throat sores grade 2+
  select id into tid from public.symptom_term where pro_ctcae_code = 'G6';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":2}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":2}'::jsonb, 'info', '{"route":"inbox"}'::jsonb);
  end if;

  -- Info: trouble sleeping grade 2+
  select id into tid from public.symptom_term where pro_ctcae_code = 'PS3';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":2}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":2}'::jsonb, 'info', '{"route":"inbox"}'::jsonb);
  end if;

  -- Info: decreased appetite grade 2+
  select id into tid from public.symptom_term where pro_ctcae_code = 'G5';
  select id into rid from public.alert_rule where term_id = tid and condition @> '{"min_grade":2}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (tid, '{"min_grade":2}'::jsonb, 'info', '{"route":"inbox"}'::jsonb);
  end if;

  -- Cross-cutting: 3+ concurrent grade 2+ symptoms → urgent
  select id into rid from public.alert_rule where term_id is null and condition @> '{"concurrent":3}'::jsonb limit 1;
  if rid is null then
    insert into public.alert_rule (term_id, condition, severity_level, escalation)
    values (null, '{"min_grade":2,"concurrent":3}'::jsonb, 'urgent', '{"route":"inbox","label":"multiple symptoms"}'::jsonb);
  end if;
end $$;
