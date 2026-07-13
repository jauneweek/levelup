-- ============================================================================
-- LEVELUP — Test pgTAP : moteur de notifications (M3)
-- Lancé par `supabase test db` (npm run test).
-- get_due_notifications() dépend de now() réel : offsets relatifs (now() +
-- interval), pas de dates fixes (contrairement à close_day_test.sql).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(15);

-- ============================================================================
-- interpolate_template
-- ============================================================================
select is(
  interpolate_template('{habit} dans {minutes_left} min, +{xp} XP',
    jsonb_build_object('habit', 'lecture', 'minutes_left', 12, 'xp', 25)),
  'lecture dans 12 min, +25 XP',
  'interpolate_template: remplace toutes les variables'
);

-- ============================================================================
-- get_notification_context
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-000000000001', 'ctx@test.dev', '{"timezone":"UTC"}'::jsonb);

select is(
  (get_notification_context('c0000000-0000-0000-0000-000000000001')->>'is_slump')::boolean,
  false, 'get_notification_context: pas de slump par défaut (aucun historique)'
);
select is(
  (get_notification_context('c0000000-0000-0000-0000-000000000001')->>'is_regular')::boolean,
  false, 'get_notification_context: pas régulier non plus par défaut (aucun historique)'
);

-- Compte neuf avec une habitude créée aujourd'hui (0 jour vécu) : trouvé en
-- testant M3 sur un vrai iPhone — se retrouvait classé "slump" par défaut,
-- ce qui écrasait l'escalade dès le tout premier rappel.
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000f', 'fresh@test.dev', '{"timezone":"UTC"}'::jsonb);
insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency)
values ('c0000000-0000-0000-0000-000000000ffa',
        'c0000000-0000-0000-0000-00000000000f', 'toute nouvelle', 'FOR', 'easy',
        'daily', 1);

select is(
  (get_notification_context('c0000000-0000-0000-0000-00000000000f')->>'is_slump')::boolean,
  false, 'compte neuf (habitude créée aujourd''hui, 0 historique) : pas slump'
);
select is(
  (get_notification_context('c0000000-0000-0000-0000-00000000000f')->>'is_regular')::boolean,
  false, 'compte neuf (habitude créée aujourd''hui, 0 historique) : pas régulier non plus'
);

-- ============================================================================
-- Scénario A — T-30 basique + idempotence après log
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000a', 'a@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values ('c0000000-0000-0000-0000-00000000aaaa',
        'c0000000-0000-0000-0000-00000000000a', 'sport', 'FOR', 'hard',
        'daily', 1,
        (now() + interval '28 minutes')::time, now() - interval '30 days');

select is(
  (select count(*)::int from get_due_notifications()
   where user_id = 'c0000000-0000-0000-0000-00000000000a'),
  1, 'get_due_notifications: 1 candidat en fenêtre T-30'
);
select is(
  (select trigger_type from get_due_notifications()
   where user_id = 'c0000000-0000-0000-0000-00000000000a'),
  't30', 'get_due_notifications: trigger_type = t30'
);

-- On logge la notif retournée (simule l'Edge Function après envoi).
select record_notification_sent(
  'c0000000-0000-0000-0000-00000000000a',
  (select template_id from get_due_notifications()
   where user_id = 'c0000000-0000-0000-0000-00000000000a'),
  'c0000000-0000-0000-0000-00000000aaaa'
);

select is(
  (select count(*)::int from get_due_notifications()
   where user_id = 'c0000000-0000-0000-0000-00000000000a'),
  0, 'get_due_notifications: idempotent (déjà loggée -> plus candidate)'
);

-- ============================================================================
-- Scénario B — Escalade T-15 : T-30 ignorée sur la MÊME habitude -> système
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000b', 'b@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values ('c0000000-0000-0000-0000-00000000bbbb',
        'c0000000-0000-0000-0000-00000000000b', 'lecture', 'INT', 'easy',
        'daily', 1,
        (now() + interval '13 minutes')::time, now() - interval '8 days');

-- Historique sain les 6 jours précédents (pas aujourd'hui) : garde
-- completion_rate_7d au-dessus de 40%, évite un faux is_slump qui
-- prendrait le pas sur l'escalade "ignorée" testée ici (§4.4 : le
-- slump priorise sur tout le reste).
do $$
declare d date;
begin
  for d in select generate_series(current_date - 6, current_date - 2, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned)
    values ('c0000000-0000-0000-0000-00000000bbbb', 'c0000000-0000-0000-0000-00000000000b',
            d, d::timestamptz + interval '10 hours', 10);
  end loop;
end $$;

-- Simule un T-30 déjà envoyé et ignoré pour cette habitude aujourd'hui.
select record_notification_sent(
  'c0000000-0000-0000-0000-00000000000b',
  (select id from notification_templates where trigger_type = 't30' and active limit 1),
  'c0000000-0000-0000-0000-00000000bbbb'
);

select is(
  (select nt.persona from get_due_notifications() gdn
   join notification_templates nt on nt.id = gdn.template_id
   where gdn.user_id = 'c0000000-0000-0000-0000-00000000000b'),
  'system', 'escalade: T-30 ignorée -> T-15 en persona système (même habitude)'
);

-- ============================================================================
-- Scénario C — 2 ignorées dans la journée -> dernier rappel en Boss
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000c', 'c@test.dev', '{"timezone":"UTC"}'::jsonb);

-- 2 habitudes déjà "ignorées" aujourd'hui (notif envoyée, jamais complétées).
insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values
  ('c0000000-0000-0000-0000-0000000000c1',
   'c0000000-0000-0000-0000-00000000000c', 'habit1', 'FOR', 'easy',
   'daily', 1, '23:59', now() - interval '8 days'),
  ('c0000000-0000-0000-0000-0000000000c2',
   'c0000000-0000-0000-0000-00000000000c', 'habit2', 'INT', 'easy',
   'daily', 1, '23:59', now() - interval '8 days'),
  ('c0000000-0000-0000-0000-0000000000c3',
   'c0000000-0000-0000-0000-00000000000c', 'habit3 (celle qui teste)', 'SAG', 'easy',
   'daily', 1, (now() + interval '13 minutes')::time,
   now() - interval '8 days');

-- Historique sain (pas aujourd'hui) sur les 3 habitudes : évite un faux
-- is_slump qui prendrait le pas sur la règle « 2 ignorées -> Boss ».
do $$
declare d date; hid uuid;
begin
  foreach hid in array array[
    'c0000000-0000-0000-0000-0000000000c1'::uuid,
    'c0000000-0000-0000-0000-0000000000c2'::uuid,
    'c0000000-0000-0000-0000-0000000000c3'::uuid
  ]
  loop
    for d in select generate_series(current_date - 6, current_date - 2, interval '1 day')::date
    loop
      insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned)
      values (hid, 'c0000000-0000-0000-0000-00000000000c',
              d, d::timestamptz + interval '10 hours', 10);
    end loop;
  end loop;
end $$;

select record_notification_sent('c0000000-0000-0000-0000-00000000000c',
  (select id from notification_templates where trigger_type = 't30' and active limit 1),
  'c0000000-0000-0000-0000-0000000000c1');
select record_notification_sent('c0000000-0000-0000-0000-00000000000c',
  (select id from notification_templates where trigger_type = 't30' and active limit 1),
  'c0000000-0000-0000-0000-0000000000c2');

select is(
  (select nt.persona from get_due_notifications() gdn
   join notification_templates nt on nt.id = gdn.template_id
   where gdn.user_id = 'c0000000-0000-0000-0000-00000000000c'
     and gdn.habit_id = 'c0000000-0000-0000-0000-0000000000c3'),
  'boss', 'escalade: 2 ignorées aujourd''hui -> persona Boss sur le dernier rappel'
);

-- Collision : une 4e habitude dont le T-30 PROPRE a aussi été ignoré,
-- ET le compteur du jour est déjà à 2 -> le Boss doit gagner sur le
-- système (sinon la règle Boss ne se déclenche quasiment jamais, vu qu'à
-- T-15 le T-30 de CETTE habitude est presque toujours déjà ignoré).
-- Bug trouvé en testant M3 sur un vrai iPhone.
insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values ('c0000000-0000-0000-0000-0000000000c4',
        'c0000000-0000-0000-0000-00000000000c', 'habit4 (collision)', 'PRO', 'easy',
        'daily', 1, (now() + interval '13 minutes')::time,
        now() - interval '8 days');

do $$
declare d date;
begin
  for d in select generate_series(current_date - 6, current_date - 2, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned)
    values ('c0000000-0000-0000-0000-0000000000c4', 'c0000000-0000-0000-0000-00000000000c',
            d, d::timestamptz + interval '10 hours', 10);
  end loop;
end $$;

select record_notification_sent('c0000000-0000-0000-0000-00000000000c',
  (select id from notification_templates where trigger_type = 't30' and active limit 1),
  'c0000000-0000-0000-0000-0000000000c4');

select is(
  (select nt.persona from get_due_notifications() gdn
   join notification_templates nt on nt.id = gdn.template_id
   where gdn.user_id = 'c0000000-0000-0000-0000-00000000000c'
     and gdn.habit_id = 'c0000000-0000-0000-0000-0000000000c4'),
  'boss', 'escalade: collision (T-30 propre ignoré + 2 ignorées) -> Boss gagne sur système'
);

-- ============================================================================
-- Scénario D — is_slump : uniquement tone supportive, jamais le Boss
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000d', 'd@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values ('c0000000-0000-0000-0000-00000000dddd',
        'c0000000-0000-0000-0000-00000000000d', 'quête slump', 'PRO', 'easy',
        'daily', 1,
        (now() + interval '28 minutes')::time, now() - interval '10 days');

-- 7 jours d'historique très bas (rate << 40%) : 1 seule complétion sur 7.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned)
values ('c0000000-0000-0000-0000-00000000dddd', 'c0000000-0000-0000-0000-00000000000d',
        current_date - 1, now() - interval '1 day', 10);

select is(
  (get_notification_context('c0000000-0000-0000-0000-00000000000d')->>'is_slump')::boolean,
  true, 'contexte: slump détecté (1/7 jours complétés)'
);
select is(
  (select nt.tone from get_due_notifications() gdn
   join notification_templates nt on nt.id = gdn.template_id
   where gdn.user_id = 'c0000000-0000-0000-0000-00000000000d'),
  'supportive', 'escalade: mode slump -> uniquement des templates supportive'
);

-- ============================================================================
-- Scénario E — is_regular : T-30 supprimée (T-15 uniquement)
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c0000000-0000-0000-0000-00000000000e', 'e@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, deadline_time, created_at)
values ('c0000000-0000-0000-0000-00000000eeee',
        'c0000000-0000-0000-0000-00000000000e', 'quête régulière', 'END', 'easy',
        'daily', 1,
        (now() + interval '28 minutes')::time, now() - interval '10 days');

-- 7 jours d'historique quasi parfait (rate > 85%).
do $$
declare d date;
begin
  for d in select generate_series(current_date - 7, current_date - 1, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned)
    values ('c0000000-0000-0000-0000-00000000eeee', 'c0000000-0000-0000-0000-00000000000e',
            d, d::timestamptz + interval '10 hours', 10);
  end loop;
end $$;

select is(
  (get_notification_context('c0000000-0000-0000-0000-00000000000e')->>'is_regular')::boolean,
  true, 'contexte: régulier détecté (7/7 jours complétés)'
);
select is(
  (select count(*)::int from get_due_notifications()
   where user_id = 'c0000000-0000-0000-0000-00000000000e'),
  0, 'escalade: utilisateur régulier -> T-30 supprimée'
);

select * from finish();
rollback;
