-- ============================================================================
-- LEVELUP — Test pgTAP : Journée complète (M5) — todos, rituel du soir,
-- morning brief, donjon instantané. Lancé par `supabase test db`.
-- Dates fixes pour close_day() ; date réelle pour complete_todo()/
-- complete_habit_express() (comme complete_habit_test.sql).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(29);

-- ============================================================================
-- Scénario A — complete_todo() : quête secrète sur une todo, bonus journée
-- parfaite combiné habitude+todo, idempotence, garde de date
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('da111111-1111-1111-1111-111111111111', 'a@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule)
values
  ('da222222-2222-2222-2222-222222222222',
   'da111111-1111-1111-1111-111111111111', 'quête A FOR', 'FOR', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('da222223-2222-2222-2222-222222222223',
   'da111111-1111-1111-1111-111111111111', 'quête A INT', 'INT', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb);

insert into todos (id, user_id, title, stat, difficulty, date)
values ('da333333-3333-3333-3333-333333333333',
        'da111111-1111-1111-1111-111111111111', 'todo A', 'INT', 'easy', current_date);

insert into secret_quests (user_id, date, target_type, target_id, reward)
values ('da111111-1111-1111-1111-111111111111', current_date, 'todo',
        'da333333-3333-3333-3333-333333333333', jsonb_build_object('type', 'xp_double'));

-- Quête hebdo INT (pour vérifier que les todos NE la font PAS progresser —
-- SPEC §3.5 : "habitudes de {stat}", lecture littérale).
select generate_weekly_quests('da111111-1111-1111-1111-111111111111', '2026-01-05');

select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select results_eq(
  $$ select (complete_habit('da222222-2222-2222-2222-222222222222')->>'xp_earned')::int $$,
  $$ values (10) $$,
  'complete_habit: 1ère des 3 quêtes du jour (2 habitudes + 1 todo) -> XP normal (10)'
);
select results_eq(
  $$ select (complete_habit('da222223-2222-2222-2222-222222222223')->>'xp_earned')::int $$,
  $$ values (10) $$,
  'complete_habit: 2e des 3 quêtes du jour -> XP normal (10), pas encore la dernière'
);
select results_eq(
  $$ select (complete_todo('da333333-3333-3333-3333-333333333333')->>'xp_earned')::int $$,
  $$ values (30) $$,
  'complete_todo: dernière des 3 -> secret x2 * bonus journée parfaite x1.5 = x3, cap ok (10*3=30)'
);
select results_eq(
  $$ select complete_todo('da333333-3333-3333-3333-333333333333')->>'already_completed' $$,
  $$ values ('true') $$,
  'complete_todo: idempotent (2e appel même jour)'
);

reset role;

select is(
  (select revealed from secret_quests
   where user_id = 'da111111-1111-1111-1111-111111111111' and date = current_date),
  true, 'quête secrète (todo): marquée révélée'
);
select is(
  (select progress from quests
   where user_id = 'da111111-1111-1111-1111-111111111111' and type = 'weekly'
     and (definition ->> 'stat') = 'INT'),
  1, 'quête hebdo INT: progresse via l''habitude (1) mais pas via la todo ensuite (reste à 1)'
);

-- Garde de date : une todo pour demain ne peut pas être complétée aujourd'hui.
insert into todos (id, user_id, title, stat, difficulty, date)
values ('da444444-4444-4444-4444-444444444444',
        'da111111-1111-1111-1111-111111111111', 'todo demain', 'SAG', 'easy',
        current_date + 1);

select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$ select complete_todo('da444444-4444-4444-4444-444444444444') $$, 'P0001', null,
  'complete_todo: refuse une todo dont la date n''est pas aujourd''hui'
);
reset role;

-- ============================================================================
-- Scénario B — Rituel du soir (§3.8) : +10 XP PRO à la 1ère todo de demain
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('db111111-1111-1111-1111-111111111111', 'b@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into todos (user_id, title, stat, difficulty, date)
values ('db111111-1111-1111-1111-111111111111', 'planif 1', 'PRO', 'easy', current_date + 1);

select is(
  (select current_xp from user_stats
   where user_id = 'db111111-1111-1111-1111-111111111111' and stat = 'PRO'),
  10, 'rituel du soir: +10 XP PRO à la 1ère todo créée pour demain'
);

insert into todos (user_id, title, stat, difficulty, date)
values ('db111111-1111-1111-1111-111111111111', 'planif 2', 'PRO', 'easy', current_date + 1);

select is(
  (select current_xp from user_stats
   where user_id = 'db111111-1111-1111-1111-111111111111' and stat = 'PRO'),
  10, 'rituel du soir: pas de double récompense (2e todo pour demain le même jour)'
);

insert into todos (user_id, title, stat, difficulty, date)
values ('db111111-1111-1111-1111-111111111111', 'planif surlendemain', 'PRO', 'easy', current_date + 2);

select is(
  (select current_xp from user_stats
   where user_id = 'db111111-1111-1111-1111-111111111111' and stat = 'PRO'),
  10, 'rituel du soir: pas de récompense pour une todo qui n''est pas pour demain'
);

-- ============================================================================
-- Scénario C — Donjon Instantané (§3.10) : 50% XP, cap 2/jour, streak
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('dc111111-1111-1111-1111-111111111111', 'c@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, minimal_version)
values
  ('dc222222-2222-2222-2222-222222222222',
   'dc111111-1111-1111-1111-111111111111', 'quête C1', 'FOR', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb, '5 pompes'),
  ('dc333333-3333-3333-3333-333333333333',
   'dc111111-1111-1111-1111-111111111111', 'quête C2', 'INT', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2 pages'),
  ('dc444444-4444-4444-4444-444444444444',
   'dc111111-1111-1111-1111-111111111111', 'quête C3', 'SAG', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2 min de méditation'),
  ('dc555555-5555-5555-5555-555555555555',
   'dc111111-1111-1111-1111-111111111111', 'quête C4 sans version min', 'PRO', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb, null);

-- Quête hebdo FOR, pour vérifier qu'une complétion express la fait progresser
-- (contrairement aux todos, ci-dessus — l'express reste une vraie complétion
-- d'habitude, juste à taux réduit).
select generate_weekly_quests('dc111111-1111-1111-1111-111111111111', '2026-01-05');

select set_config(
  'request.jwt.claims',
  '{"sub":"dc111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select results_eq(
  $$ select (complete_habit_express('dc222222-2222-2222-2222-222222222222')->>'xp_earned')::int $$,
  $$ values (5) $$,
  'donjon express: 50% de l''XP (10*0.5=5)'
);
select results_eq(
  $$ select (complete_habit_express('dc333333-3333-3333-3333-333333333333')->>'xp_earned')::int $$,
  $$ values (5) $$,
  'donjon express: 2e complétion express de la journée (5 XP)'
);
select results_eq(
  $$ select complete_habit_express('dc444444-4444-4444-4444-444444444444')->>'express_limit_reached' $$,
  $$ values ('true') $$,
  'donjon express: limite de 2/jour atteinte à la 3e tentative'
);
select throws_ok(
  $$ select complete_habit_express('dc555555-5555-5555-5555-555555555555') $$, 'P0001', null,
  'donjon express: refusé si l''habitude n''a pas de version minimale'
);

reset role;

select is(
  (select is_express from habit_logs
   where habit_id = 'dc222222-2222-2222-2222-222222222222' and date = current_date),
  true, 'donjon express: is_express=true loggé'
);
select is(
  (select current from streaks
   where user_id = 'dc111111-1111-1111-1111-111111111111'
     and habit_id = 'dc222222-2222-2222-2222-222222222222'),
  1, 'donjon express: streak de l''habitude préservé/incrémenté (1er jour)'
);
select is(
  (select progress from quests
   where user_id = 'dc111111-1111-1111-1111-111111111111' and type = 'weekly'
     and (definition ->> 'stat') = 'FOR'),
  1, 'quête hebdo FOR: une complétion express compte comme une vraie complétion'
);

-- ============================================================================
-- Scénario D — close_day() : todos dans le taux du jour et les pénalités
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('dd111111-1111-1111-1111-111111111111', 'd@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('dd222222-2222-2222-2222-222222222222',
        'dd111111-1111-1111-1111-111111111111', 'quête D', 'FOR', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

update user_stats set current_xp = 100
  where user_id = 'dd111111-1111-1111-1111-111111111111' and stat = 'INT';

-- Jour 1 : habitude faite, todo ratée -> pas parfait, todo pénalisée.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('dd222222-2222-2222-2222-222222222222',
        'dd111111-1111-1111-1111-111111111111', '2026-01-01', '2026-01-01 12:00:00+00', 10, 1.0);
insert into todos (user_id, title, stat, difficulty, date)
values ('dd111111-1111-1111-1111-111111111111', 'todo D1', 'INT', 'easy', '2026-01-01');

select results_eq(
  $$ select (close_day('dd111111-1111-1111-1111-111111111111','2026-01-01')->>'day_rate')::numeric $$,
  $$ values (0.5::numeric) $$,
  'close_day: taux du jour = 1 habitude + 0 todo sur 2 (habitude + todo) = 0.5'
);
select is(
  (select xp_earned from todos
   where user_id = 'dd111111-1111-1111-1111-111111111111' and date = '2026-01-01'),
  -4, 'close_day: todo ratée pénalisée (10*0.4*1 = 4, stocké en négatif)'
);
select is(
  (select current_xp from user_stats
   where user_id = 'dd111111-1111-1111-1111-111111111111' and stat = 'INT'),
  96, 'close_day: XP de la stat de la todo déduite (100 -> 96)'
);

-- Jour 2 : habitude faite, todo faite -> journée parfaite grâce à la todo.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('dd222222-2222-2222-2222-222222222222',
        'dd111111-1111-1111-1111-111111111111', '2026-01-02', '2026-01-02 12:00:00+00', 10, 1.0);
insert into todos (user_id, title, stat, difficulty, date, completed_at, xp_earned)
values ('dd111111-1111-1111-1111-111111111111', 'todo D2', 'SAG', 'easy', '2026-01-02',
        '2026-01-02 12:00:00+00', 10);

select results_eq(
  $$ select close_day('dd111111-1111-1111-1111-111111111111','2026-01-02')->>'is_perfect_day' $$,
  $$ values ('true') $$,
  'close_day: journée parfaite (habitude + todo toutes deux complétées)'
);
select is(
  (select current from streaks
   where user_id = 'dd111111-1111-1111-1111-111111111111' and habit_id is null),
  1, 'close_day: streak global = 1 (la todo complétée contribue à la journée parfaite)'
);

-- ============================================================================
-- Scénario E — Morning brief (§3.8)
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('de111111-1111-1111-1111-111111111111', 'e@test.dev', '{"timezone":"UTC"}'::jsonb);

select send_morning_brief('de111111-1111-1111-1111-111111111111');

select is(
  (select count(*)::int from notification_queue
   where user_id = 'de111111-1111-1111-1111-111111111111' and trigger_type = 'morning_brief'),
  1, 'morning brief: 1 annonce mise en file'
);
select is(
  (select vars ->> 'rank' from notification_queue
   where user_id = 'de111111-1111-1111-1111-111111111111' and trigger_type = 'morning_brief'),
  'E', 'morning brief: rang correct (E par défaut)'
);
select is(
  (select vars ->> 'streak' from notification_queue
   where user_id = 'de111111-1111-1111-1111-111111111111' and trigger_type = 'morning_brief'),
  '0', 'morning brief: streak correct (0 par défaut)'
);

-- ============================================================================
-- Anti-triche : todos — grants colonne (completed_at/xp_earned système-only)
-- ============================================================================
select set_config(
  'request.jwt.claims',
  '{"sub":"da111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$ update todos set completed_at = now()
     where id = 'da444444-4444-4444-4444-444444444444' $$,
  '42501', null,
  'anti-triche: écriture directe de todos.completed_at refusée'
);
select throws_ok(
  $$ update todos set xp_earned = 9999
     where id = 'da444444-4444-4444-4444-444444444444' $$,
  '42501', null,
  'anti-triche: écriture directe de todos.xp_earned refusée'
);
select throws_ok(
  $$ insert into todos (user_id, title, stat, difficulty, date, completed_at) values
     ('da111111-1111-1111-1111-111111111111', 'triche', 'FOR', 'easy', current_date, now()) $$,
  '42501', null,
  'anti-triche: impossible de créer une todo déjà "complétée"'
);
select lives_ok(
  $$ insert into todos (user_id, title, stat, difficulty, date) values
     ('da111111-1111-1111-1111-111111111111', 'todo normale', 'FOR', 'easy', current_date) $$,
  'RLS: création normale d''une todo (sans completed_at) autorisée'
);

reset role;
select * from finish();
rollback;
