-- ============================================================================
-- LEVELUP — Test pgTAP : close_day() / Tribunal de minuit (M2)
-- Lancé par `supabase test db` (npm run test).
-- Dates fixes (2026-01-xx / 2026-02-xx) : déterministe, indépendant de now().
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(24);

-- ============================================================================
-- Scénario A — User U : escalade des pénalités, plancher 0, malus visible
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('55555555-5555-5555-5555-555555555555', 'u@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('66666666-6666-6666-6666-666666666666',
        '55555555-5555-5555-5555-555555555555', 'quête U', 'FOR', 'hard',
        'daily', 1, '2025-01-01');

-- current_xp de départ suffisamment haut pour observer la progression, puis
-- suffisamment bas pour tester le plancher 0 au 4e jour d'abus.
update user_stats set current_xp = 100
  where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR';

-- Padding : Dec25-31 complétées (7 jours) pour garder completion_rate_7d
-- au-dessus de 40% pendant que Jan1-4 sont ratés (jours d'abus).
do $$
declare d date;
begin
  for d in select generate_series('2025-12-25'::date, '2025-12-31'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('66666666-6666-6666-6666-666666666666',
            '55555555-5555-5555-5555-555555555555', d, d::timestamptz + interval '12 hours', 50, 1.0);
  end loop;
end $$;

-- Jour 1 d'abus (2026-01-01) : pénalité de base, pas d'escalade.
select results_eq(
  $$ select (close_day('55555555-5555-5555-5555-555555555555','2026-01-01')->>'penalty_multiplier')::numeric $$,
  $$ values (1.0::numeric) $$,
  'close_day J1: pas d''escalade (multiplicateur x1)'
);
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  80, 'close_day J1: 100 - (50*0.4*1) = 80'
);

-- Jour 2 d'abus consécutif (2026-01-02) : x1.5.
select results_eq(
  $$ select (close_day('55555555-5555-5555-5555-555555555555','2026-01-02')->>'penalty_multiplier')::numeric $$,
  $$ values (1.5::numeric) $$,
  'close_day J2: escalade x1.5 (2e jour consécutif)'
);
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  50, 'close_day J2: 80 - (50*0.4*1.5) = 50'
);

-- Jour 3 d'abus consécutif (2026-01-03) : x2.
select results_eq(
  $$ select (close_day('55555555-5555-5555-5555-555555555555','2026-01-03')->>'penalty_multiplier')::numeric $$,
  $$ values (2.0::numeric) $$,
  'close_day J3: escalade x2 (3e jour et +)'
);
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  10, 'close_day J3: 50 - (50*0.4*2) = 10'
);

-- Jour 4 (2026-01-04) : x2 toujours (cap), plancher 0 (10 - 40 < 0).
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  10, 'sanity: xp = 10 avant J4'
);
select results_eq(
  $$ select (close_day('55555555-5555-5555-5555-555555555555','2026-01-04')->>'penalty_multiplier')::numeric $$,
  $$ values (2.0::numeric) $$,
  'close_day J4: multiplicateur reste x2 (pas d''escalade au-delà)'
);
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  0, 'close_day J4: plancher 0 (jamais négatif)'
);

-- Malus visible : le 3e jour d'abus consécutif fait spawn le Boss (M4), ce
-- qui fixe l'état à 3 (priorité sur l'échelle 0-2) tant qu'il reste actif.
select is(
  (select emblem_damage from profiles where id = '55555555-5555-5555-5555-555555555555'),
  3, 'malus visible: état 3 (boss actif, spawné au 3e jour d''abus consécutif, M4)'
);

-- Streak par habitude reset à 0 après un jour raté.
select is(
  (select current from streaks
   where user_id = '55555555-5555-5555-5555-555555555555'
     and habit_id = '66666666-6666-6666-6666-666666666666'),
  0, 'streak habitude reset à 0 après jour raté'
);

-- Jour 5 (2026-01-05) : journée parfaite -> le Boss encaisse 1 PV (M4) mais
-- reste actif, donc le malus visible reste fixé à l'état 3.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('66666666-6666-6666-6666-666666666666',
        '55555555-5555-5555-5555-555555555555', '2026-01-05',
        '2026-01-05 12:00:00+00', 50, 1.0);

select results_eq(
  $$ select close_day('55555555-5555-5555-5555-555555555555','2026-01-05')->>'is_perfect_day' $$,
  $$ values ('true') $$,
  'close_day J5: journée parfaite détectée'
);
select is(
  (select emblem_damage from profiles where id = '55555555-5555-5555-5555-555555555555'),
  3, 'malus visible: reste à l''état 3 (le Boss encaisse 1 PV mais reste actif, M4)'
);

-- Idempotence : rejouer J1 ne repénalise pas.
select results_eq(
  $$ select close_day('55555555-5555-5555-5555-555555555555','2026-01-01')->>'already_processed' $$,
  $$ values ('true') $$,
  'close_day: idempotent (rejouer J1 renvoie already_processed)'
);
select is(
  (select current_xp from user_stats
   where user_id = '55555555-5555-5555-5555-555555555555' and stat = 'FOR'),
  0, 'close_day: rejouer J1 ne change pas l''XP (toujours 0)'
);

-- ============================================================================
-- Scénario B — User V : streak global, bouclier gagné puis consommé
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('77777777-7777-7777-7777-777777777777', 'v@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('88888888-8888-8888-8888-888888888888',
        '77777777-7777-7777-7777-777777777777', 'quête V', 'INT', 'easy',
        'daily', 1, '2025-01-01');

-- 10 journées parfaites consécutives (2026-02-01 .. 2026-02-10).
do $$
declare d date;
begin
  for d in select generate_series('2026-02-01'::date, '2026-02-10'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('88888888-8888-8888-8888-888888888888',
            '77777777-7777-7777-7777-777777777777', d, d::timestamptz + interval '12 hours', 10, 1.0);
    perform close_day('77777777-7777-7777-7777-777777777777', d);
  end loop;
end $$;

select is(
  (select current from streaks
   where user_id = '77777777-7777-7777-7777-777777777777' and habit_id is null),
  10, 'streak global = 10 après 10 journées parfaites'
);
select is(
  (select shields from streaks
   where user_id = '77777777-7777-7777-7777-777777777777' and habit_id is null),
  1, 'bouclier gagné au palier des 10 jours'
);

-- Jour 11 raté, bouclier disponible -> consommé, streak figé (pas reset).
select is(
  (close_day('77777777-7777-7777-7777-777777777777','2026-02-11')->>'shields')::int,
  0, 'bouclier consommé (1 -> 0) sur journée ratée'
);
select is(
  (select current from streaks
   where user_id = '77777777-7777-7777-7777-777777777777' and habit_id is null),
  10, 'streak figé à 10 (protégé par le bouclier, ni +1 ni reset)'
);

-- Jour 12 raté, plus de bouclier -> streak reset à 0.
select close_day('77777777-7777-7777-7777-777777777777','2026-02-12');
select is(
  (select current from streaks
   where user_id = '77777777-7777-7777-7777-777777777777' and habit_id is null),
  0, 'streak reset à 0 (plus de bouclier)'
);

-- ============================================================================
-- Scénario C — complete_habit() : bonus journée parfaite ×1.5 (M2)
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('99999999-9999-9999-9999-999999999999', 'w@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '99999999-9999-9999-9999-999999999999', 'facile W', 'FOR', 'easy',
   'daily', 1),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '99999999-9999-9999-9999-999999999999', 'moyenne W', 'INT', 'medium',
   'daily', 1);

select set_config(
  'request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}',
  true
);
set local role authenticated;

-- 1ère des 2 habitudes du jour : pas encore la dernière, XP plein sans bonus.
select results_eq(
  $$ select (complete_habit('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')->>'xp_earned')::int $$,
  $$ values (10) $$,
  'complete_habit: 1ère habitude du jour, pas de bonus journée parfaite'
);

-- 2e et dernière habitude du jour : bonus x1.5 (journée parfaite).
select results_eq(
  $$ select (complete_habit('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')->>'xp_earned')::int $$,
  $$ values (38) $$,
  'complete_habit: dernière habitude du jour -> bonus x1.5 (25*1.5=37.5 arrondi 38)'
);

reset role;

-- ============================================================================
-- Anti-cheat : close_day / run_midnight_close réservées au serveur
-- ============================================================================
select set_config(
  'request.jwt.claims',
  '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$ select close_day('55555555-5555-5555-5555-555555555555', current_date) $$,
  '42501', null,
  'anti-triche: authenticated ne peut pas appeler close_day directement'
);
select throws_ok(
  $$ select run_midnight_close() $$,
  '42501', null,
  'anti-triche: authenticated ne peut pas appeler run_midnight_close directement'
);

reset role;
select * from finish();
rollback;
