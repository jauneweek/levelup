-- ============================================================================
-- LEVELUP — Test pgTAP : Meta-game (M4) — boss, titres, quêtes, événements,
-- quête secrète. Lancé par `supabase test db` (npm run test).
-- Dates fixes (2025-12-xx / 2026-01-xx) sauf pour complete_habit() (utilise
-- toujours la date réelle du serveur, comme complete_habit_test.sql).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(59);

-- ============================================================================
-- Scénario A — Titres de streak (§3.4) : palier 7 jours, idempotence
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c1111111-1111-1111-1111-111111111111', 'a@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('c2222222-2222-2222-2222-222222222222',
        'c1111111-1111-1111-1111-111111111111', 'quête A', 'FOR', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

do $$
declare d date;
begin
  for d in select generate_series('2026-01-01'::date, '2026-01-07'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('c2222222-2222-2222-2222-222222222222',
            'c1111111-1111-1111-1111-111111111111', d, d::timestamptz + interval '12 hours', 10, 1.0);
    perform close_day('c1111111-1111-1111-1111-111111111111', d);
  end loop;
end $$;

select ok(
  exists (
    select 1 from user_titles ut join titles t on t.id = ut.title_id
    where ut.user_id = 'c1111111-1111-1111-1111-111111111111' and t.name = 'Éveillé'
  ),
  'titre "Éveillé" débloqué au palier des 7 jours de streak global'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c1111111-1111-1111-1111-111111111111' and trigger_type = 'streak_milestone'),
  1, 'notification_queue: 1 annonce streak_milestone'
);

-- Jour 8, streak parfait aussi : pas de re-déblocage (idempotence).
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c2222222-2222-2222-2222-222222222222',
        'c1111111-1111-1111-1111-111111111111', '2026-01-08',
        '2026-01-08 12:00:00+00', 10, 1.0);
select close_day('c1111111-1111-1111-1111-111111111111', '2026-01-08');

select is(
  (select count(*)::int from user_titles ut join titles t on t.id = ut.title_id
   where ut.user_id = 'c1111111-1111-1111-1111-111111111111' and t.name = 'Éveillé'),
  1, 'titre "Éveillé" : pas de doublon au jour 8'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c1111111-1111-1111-1111-111111111111' and trigger_type = 'streak_milestone'),
  1, 'notification_queue: toujours 1 seule annonce streak_milestone'
);

-- ============================================================================
-- Scénario B — Boss (§3.7) : spawn, dégâts, défaite, récompenses
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c3333333-3333-3333-3333-333333333333', 'b@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('c4444444-4444-4444-4444-444444444444',
        'c3333333-3333-3333-3333-333333333333', 'quête B', 'FOR', 'medium',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

-- Padding : garde completion_rate_7d au-dessus de 40% pendant les 3 jours
-- d'abus (évite le mode slump, qui neutraliserait l'escalade et le boss).
do $$
declare d date;
begin
  for d in select generate_series('2025-12-25'::date, '2025-12-31'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('c4444444-4444-4444-4444-444444444444',
            'c3333333-3333-3333-3333-333333333333', d, d::timestamptz + interval '12 hours', 25, 1.0);
  end loop;
end $$;

-- Jan 1-3 : 3 jours d'abus consécutifs -> spawn du boss au jour 3.
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-01');
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-02');
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-03');

select is(
  (select hp from boss_fights where user_id = 'c3333333-3333-3333-3333-333333333333' and status = 'active'),
  3, 'boss: spawn avec 3 PV au 3e jour d''abus consécutif'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c3333333-3333-3333-3333-333333333333' and trigger_type = 'boss_spawn'),
  1, 'notification_queue: 1 annonce boss_spawn'
);
select is(
  (select emblem_damage from profiles where id = 'c3333333-3333-3333-3333-333333333333'),
  3, 'malus visible: état 3 dès que le boss est actif'
);

-- Jan 4-5 : journées parfaites -> le boss encaisse 1 PV par jour.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c4444444-4444-4444-4444-444444444444',
        'c3333333-3333-3333-3333-333333333333', '2026-01-04', '2026-01-04 12:00:00+00', 25, 1.0);
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-04');

select is(
  (select hp from boss_fights where user_id = 'c3333333-3333-3333-3333-333333333333' and status = 'active'),
  2, 'boss: -1 PV après une journée parfaite'
);

insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c4444444-4444-4444-4444-444444444444',
        'c3333333-3333-3333-3333-333333333333', '2026-01-05', '2026-01-05 12:00:00+00', 25, 1.0);
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-05');

select is(
  (select hp from boss_fights where user_id = 'c3333333-3333-3333-3333-333333333333' and status = 'active'),
  1, 'boss: -1 PV, 2e journée parfaite consécutive'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c3333333-3333-3333-3333-333333333333' and trigger_type = 'boss_damage'),
  2, 'notification_queue: 2 annonces boss_damage'
);

-- Jan 6 : 3e journée parfaite -> défaite. Récompenses : +150 XP réparti,
-- titre "Tueur de Boss", item rare.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c4444444-4444-4444-4444-444444444444',
        'c3333333-3333-3333-3333-333333333333', '2026-01-06', '2026-01-06 12:00:00+00', 25, 1.0);
select close_day('c3333333-3333-3333-3333-333333333333', '2026-01-06');

select is(
  (select status from boss_fights where user_id = 'c3333333-3333-3333-3333-333333333333'
   order by spawned_at desc limit 1),
  'defeated', 'boss: statut "defeated" après la 3e journée parfaite'
);
select ok(
  exists (
    select 1 from user_titles ut join titles t on t.id = ut.title_id
    where ut.user_id = 'c3333333-3333-3333-3333-333333333333' and t.name = 'Tueur de Boss'
  ),
  'titre "Tueur de Boss" débloqué à la défaite'
);
select ok(
  exists (
    select 1 from user_items ui join items i on i.id = ui.item_id
    where ui.user_id = 'c3333333-3333-3333-3333-333333333333' and i.rarity = 'rare' and ui.quantity >= 1
  ),
  'item rare accordé à la défaite du boss'
);
select is(
  (select current_xp from user_stats
   where user_id = 'c3333333-3333-3333-3333-333333333333' and stat = 'FOR'),
  30, '+150 XP réparti: FOR reçoit 30 XP (150/5)'
);
select is(
  (select current_xp from user_stats
   where user_id = 'c3333333-3333-3333-3333-333333333333' and stat = 'SAG'),
  30, '+150 XP réparti: SAG (stat non liée à l''habitude) reçoit aussi 30 XP'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c3333333-3333-3333-3333-333333333333' and trigger_type = 'boss_defeat'),
  1, 'notification_queue: 1 annonce boss_defeat'
);
select is(
  (select emblem_damage from profiles where id = 'c3333333-3333-3333-3333-333333333333'),
  2, 'malus visible: réparé d''un cran (3->2) le jour de la défaite (journée parfaite)'
);

-- ============================================================================
-- Scénario C — Boss : deadline (jour 11) et timeout (jour 14), pénalité 10%
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c5555555-5555-5555-5555-555555555555', 'c@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('c6666666-6666-6666-6666-666666666666',
        'c5555555-5555-5555-5555-555555555555', 'quête C', 'FOR', 'medium',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

update user_stats set current_xp = 500
  where user_id = 'c5555555-5555-5555-5555-555555555555' and stat = 'SAG';

do $$
declare d date;
begin
  for d in select generate_series('2025-12-25'::date, '2025-12-31'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('c6666666-6666-6666-6666-666666666666',
            'c5555555-5555-5555-5555-555555555555', d, d::timestamptz + interval '12 hours', 25, 1.0);
  end loop;
end $$;

-- Jan 1-3 : spawn (jamais une habitude complétée ensuite -> le boss ne
-- prend jamais de dégâts, seul son âge compte pour deadline/timeout).
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-01');
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-02');
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-03');

select is(
  (select hp from boss_fights where user_id = 'c5555555-5555-5555-5555-555555555555' and status = 'active'),
  3, 'boss C: spawn au jour 3, PV intacts'
);

do $$
declare d date;
begin
  for d in select generate_series('2026-01-04'::date, '2026-01-13'::date, interval '1 day')::date
  loop
    perform close_day('c5555555-5555-5555-5555-555555555555', d);
  end loop;
end $$;

-- Jour 14 depuis le spawn (2026-01-14, spawn = 01-03) : alerte deadline.
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-14');

select is(
  (select deadline_notified from boss_fights
   where user_id = 'c5555555-5555-5555-5555-555555555555' order by spawned_at desc limit 1),
  true, 'boss C: deadline_notified à J-3 avant le timeout (jour 11 depuis spawn)'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c5555555-5555-5555-5555-555555555555' and trigger_type = 'boss_deadline'
     and vars ->> 'stat' = 'SAG'),
  1, 'notification_queue: 1 annonce boss_deadline visant la stat la plus haute (SAG)'
);

select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-15');
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-16');
select close_day('c5555555-5555-5555-5555-555555555555', '2026-01-17');

select is(
  (select status from boss_fights
   where user_id = 'c5555555-5555-5555-5555-555555555555' order by spawned_at desc limit 1),
  'timeout', 'boss C: statut "timeout" après 14 jours sans défaite'
);
select is(
  (select current_xp from user_stats
   where user_id = 'c5555555-5555-5555-5555-555555555555' and stat = 'SAG'),
  450, 'timeout: 10% de la stat la plus haute ponctionnés (500 -> 450), jamais le niveau'
);

-- ============================================================================
-- Scénario D — Quête de rédemption (§3.5) : streak cassé sans bouclier
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c7777777-7777-7777-7777-777777777777', 'd@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('c8888888-8888-8888-8888-888888888888',
        'c7777777-7777-7777-7777-777777777777', 'quête D', 'FOR', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

-- 9 journées parfaites : streak=9, pas de bouclier gagné (palier 10 non atteint).
do $$
declare d date;
begin
  for d in select generate_series('2026-01-01'::date, '2026-01-09'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('c8888888-8888-8888-8888-888888888888',
            'c7777777-7777-7777-7777-777777777777', d, d::timestamptz + interval '12 hours', 10, 1.0);
    perform close_day('c7777777-7777-7777-7777-777777777777', d);
  end loop;
end $$;

-- Jour 10 : raté, pas de bouclier -> streak cassé, quête de rédemption créée.
select close_day('c7777777-7777-7777-7777-777777777777', '2026-01-10');

select is(
  (select (definition ->> 'old_streak')::int from quests
   where user_id = 'c7777777-7777-7777-7777-777777777777' and type = 'redemption' and status = 'active'),
  9, 'rédemption: quête créée avec old_streak=9'
);
select is(
  (select count(*)::int from notification_queue
   where user_id = 'c7777777-7777-7777-7777-777777777777' and trigger_type = 'redemption'
     and (vars ->> 'streak')::int = 9),
  1, 'notification_queue: 1 annonce redemption (streak=9)'
);
select is(
  (select current from streaks
   where user_id = 'c7777777-7777-7777-7777-777777777777' and habit_id is null),
  0, 'rédemption: streak global cassé à 0'
);

-- Jour 11-12 : 2 journées parfaites -> progression de la quête.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c8888888-8888-8888-8888-888888888888',
        'c7777777-7777-7777-7777-777777777777', '2026-01-11', '2026-01-11 12:00:00+00', 10, 1.0);
select close_day('c7777777-7777-7777-7777-777777777777', '2026-01-11');

select is(
  (select progress from quests
   where user_id = 'c7777777-7777-7777-7777-777777777777' and type = 'redemption'),
  1, 'rédemption: progression 1/3 après 1 journée parfaite'
);

insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c8888888-8888-8888-8888-888888888888',
        'c7777777-7777-7777-7777-777777777777', '2026-01-12', '2026-01-12 12:00:00+00', 10, 1.0);
select close_day('c7777777-7777-7777-7777-777777777777', '2026-01-12');

select is(
  (select progress from quests
   where user_id = 'c7777777-7777-7777-7777-777777777777' and type = 'redemption'),
  2, 'rédemption: progression 2/3'
);

-- Jour 13 : 3e journée parfaite -> quête complétée, streak restauré à 50%
-- de l''ancien (ceil(9*0.5)=5), au-delà de la progression naturelle (3).
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('c8888888-8888-8888-8888-888888888888',
        'c7777777-7777-7777-7777-777777777777', '2026-01-13', '2026-01-13 12:00:00+00', 10, 1.0);
select close_day('c7777777-7777-7777-7777-777777777777', '2026-01-13');

select is(
  (select status from quests
   where user_id = 'c7777777-7777-7777-7777-777777777777' and type = 'redemption'),
  'completed', 'rédemption: quête complétée au 3e jour parfait'
);
select is(
  (select current from streaks
   where user_id = 'c7777777-7777-7777-7777-777777777777' and habit_id is null),
  5, 'rédemption: streak restauré à 5 (50% de 9), au-delà des 3 gagnés naturellement'
);

-- ============================================================================
-- Scénario E1 — Événements aléatoires (§3.6) via complete_habit()
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('c9999999-9999-9999-9999-999999999999', 'e1@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule)
values
  ('caaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'c9999999-9999-9999-9999-999999999999', 'rush E', 'FOR', 'medium',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('cbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'c9999999-9999-9999-9999-999999999999', 'neutre E', 'INT', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('ccccccc0-cccc-cccc-cccc-cccccccccccc',
   'c9999999-9999-9999-9999-999999999999', 'dernière E', 'SAG', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb);

insert into events_log (user_id, event_type, date, payload)
values
  ('c9999999-9999-9999-9999-999999999999', 'rush', current_date,
   jsonb_build_object('habit_id', 'caaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('c9999999-9999-9999-9999-999999999999', 'potion', current_date, '{}'::jsonb),
  ('c9999999-9999-9999-9999-999999999999', 'chest', current_date, '{}'::jsonb);

select set_config(
  'request.jwt.claims',
  '{"sub":"c9999999-9999-9999-9999-999999999999","role":"authenticated"}',
  true
);
set local role authenticated;

select complete_habit('caaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select complete_habit('cbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select complete_habit('ccccccc0-cccc-cccc-cccc-cccccccccccc');

reset role;

-- Heure de rush : x2 si avant midi, sinon tarif normal — non déterministe
-- (dépend de l'heure réelle d'exécution des tests), on vérifie juste que
-- l'habitude ciblée ne dépasse jamais son cas nominal (25) ou doublé (50).
select ok(
  (select xp_earned from habit_logs
   where habit_id = 'caaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and date = current_date) in (25, 50),
  'événement rush: XP = base (25) ou doublé (50) selon l''heure réelle'
);
select is(
  (select xp_earned from habit_logs
   where habit_id = 'cbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and date = current_date),
  10, 'habitude non ciblée par le rush, pas la dernière du jour: XP normal (10)'
);
select is(
  (select xp_earned from habit_logs
   where habit_id = 'ccccccc0-cccc-cccc-cccc-cccccccccccc' and date = current_date),
  30, 'Potion + bonus journée parfaite: x1.5*2=x3 sur la dernière habitude (10*3=30)'
);
select is(
  (select resolved from events_log
   where user_id = 'c9999999-9999-9999-9999-999999999999' and event_type = 'chest' and date = current_date),
  true, 'coffre mystère: résolu après 3 habitudes complétées'
);
select ok(
  exists (
    select 1 from user_items ui join items i on i.id = ui.item_id
    where ui.user_id = 'c9999999-9999-9999-9999-999999999999' and i.rarity = 'common'
  ),
  'coffre mystère: item commun accordé'
);

-- ============================================================================
-- Scénario E2 — Jour maudit (§3.6) : pénalités doublées via close_day()
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('cd000001-0000-0000-0000-000000000001', 'e2@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('cd000002-0000-0000-0000-000000000002',
        'cd000001-0000-0000-0000-000000000001', 'quête E2', 'FOR', 'medium',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

do $$
declare d date;
begin
  for d in select generate_series('2025-12-25'::date, '2025-12-31'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('cd000002-0000-0000-0000-000000000002',
            'cd000001-0000-0000-0000-000000000001', d, d::timestamptz + interval '12 hours', 25, 1.0);
  end loop;
end $$;

update user_stats set current_xp = 1000
  where user_id = 'cd000001-0000-0000-0000-000000000001' and stat = 'FOR';

insert into events_log (user_id, event_type, date, payload)
values ('cd000001-0000-0000-0000-000000000001', 'cursed', '2026-01-01', '{}'::jsonb);

select results_eq(
  $$ select (close_day('cd000001-0000-0000-0000-000000000001','2026-01-01')->>'penalty_multiplier')::numeric $$,
  $$ values (2.0::numeric) $$,
  'jour maudit: pénalité doublée (x1 normal -> x2) le 1er jour d''abus'
);
select is(
  (select current_xp from user_stats
   where user_id = 'cd000001-0000-0000-0000-000000000001' and stat = 'FOR'),
  980, 'jour maudit: pénalité = 25*0.4*2 = 20 déduits (1000 -> 980)'
);

-- ============================================================================
-- Scénario F — Quête secrète (§3.14) : révélation à la complétion
-- ============================================================================
-- F1 : bonus XP x2.
insert into auth.users (id, email, raw_user_meta_data)
values ('cf000001-0000-0000-0000-000000000001', 'f1@test.dev', '{"timezone":"UTC"}'::jsonb);
insert into habits (id, user_id, name, stat, difficulty, schedule)
values
  ('cf000002-0000-0000-0000-000000000002',
   'cf000001-0000-0000-0000-000000000001', 'secrète F1a', 'FOR', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('cf000003-0000-0000-0000-000000000003',
   'cf000001-0000-0000-0000-000000000001', 'secrète F1b', 'INT', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb);
insert into secret_quests (user_id, date, target_type, target_id, reward)
values ('cf000001-0000-0000-0000-000000000001', current_date, 'habit',
        'cf000002-0000-0000-0000-000000000002', jsonb_build_object('type', 'xp_double'));

select set_config(
  'request.jwt.claims',
  '{"sub":"cf000001-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select complete_habit('cf000002-0000-0000-0000-000000000002');
reset role;

select is(
  (select xp_earned from habit_logs
   where habit_id = 'cf000002-0000-0000-0000-000000000002' and date = current_date),
  20, 'quête secrète xp_double: 10*2=20 (habitude non-dernière, pas de bonus journée parfaite)'
);
select is(
  (select revealed from secret_quests
   where user_id = 'cf000001-0000-0000-0000-000000000001' and date = current_date),
  true, 'quête secrète: marquée révélée après complétion'
);

-- F2 : bonus item.
insert into auth.users (id, email, raw_user_meta_data)
values ('cf000011-0000-0000-0000-000000000011', 'f2@test.dev', '{"timezone":"UTC"}'::jsonb);
insert into habits (id, user_id, name, stat, difficulty, schedule)
values ('cf000012-0000-0000-0000-000000000012',
        'cf000011-0000-0000-0000-000000000011', 'secrète F2', 'PRO', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb);
insert into secret_quests (user_id, date, target_type, target_id, reward)
values ('cf000011-0000-0000-0000-000000000011', current_date, 'habit',
        'cf000012-0000-0000-0000-000000000012', jsonb_build_object('type', 'item', 'rarity', 'common'));

select set_config(
  'request.jwt.claims',
  '{"sub":"cf000011-0000-0000-0000-000000000011","role":"authenticated"}',
  true
);
set local role authenticated;
select complete_habit('cf000012-0000-0000-0000-000000000012');
reset role;

select ok(
  exists (
    select 1 from user_items ui join items i on i.id = ui.item_id
    where ui.user_id = 'cf000011-0000-0000-0000-000000000011' and i.rarity = 'common'
  ),
  'quête secrète item: item commun accordé à la complétion'
);

-- F3 : bonus bouclier.
insert into auth.users (id, email, raw_user_meta_data)
values ('cf000021-0000-0000-0000-000000000021', 'f3@test.dev', '{"timezone":"UTC"}'::jsonb);
insert into habits (id, user_id, name, stat, difficulty, schedule)
values ('cf000022-0000-0000-0000-000000000022',
        'cf000021-0000-0000-0000-000000000021', 'secrète F3', 'END', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb);
insert into secret_quests (user_id, date, target_type, target_id, reward)
values ('cf000021-0000-0000-0000-000000000021', current_date, 'habit',
        'cf000022-0000-0000-0000-000000000022', jsonb_build_object('type', 'shield'));

select set_config(
  'request.jwt.claims',
  '{"sub":"cf000021-0000-0000-0000-000000000021","role":"authenticated"}',
  true
);
set local role authenticated;
select complete_habit('cf000022-0000-0000-0000-000000000022');
reset role;

select is(
  (select shields from streaks
   where user_id = 'cf000021-0000-0000-0000-000000000021' and habit_id is null),
  1, 'quête secrète bouclier: +1 bouclier de streak accordé'
);

-- ============================================================================
-- Scénario G — Quêtes hebdomadaires (§3.5) : génération, progression, reward
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('ce900001-0000-0000-0000-000000000001', 'g@test.dev', '{"timezone":"UTC"}'::jsonb);
insert into habits (id, user_id, name, stat, difficulty, schedule)
values
  ('ce900002-0000-0000-0000-000000000002',
   'ce900001-0000-0000-0000-000000000001', 'quête hebdo G1', 'FOR', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('ce900003-0000-0000-0000-000000000003',
   'ce900001-0000-0000-0000-000000000001', 'quête hebdo G2', 'FOR', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('ce900004-0000-0000-0000-000000000004',
   'ce900001-0000-0000-0000-000000000001', 'quête hebdo G3', 'INT', 'easy',
   '{"days":[1,2,3,4,5,6,7]}'::jsonb);

select generate_weekly_quests('ce900001-0000-0000-0000-000000000001', '2026-01-05');

select is(
  (select count(*)::int from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly'),
  2, 'quêtes hebdo: 2 générées (2 stats distinctes avec des habitudes)'
);
select is(
  (select target from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly' and (definition ->> 'stat') = 'FOR'),
  15, 'quête hebdo FOR: cible = fréquence habituelle (7+7) + 1 = 15'
);
select is(
  (select target from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly' and (definition ->> 'stat') = 'INT'),
  8, 'quête hebdo INT: cible = fréquence habituelle (7) + 1 = 8'
);

update quests
  set reward = jsonb_build_object('type', 'xp_bonus', 'amount', 100, 'stat', 'FOR'),
      progress = target - 1
  where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly'
    and (definition ->> 'stat') = 'FOR';

select set_config(
  'request.jwt.claims',
  '{"sub":"ce900001-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select complete_habit('ce900002-0000-0000-0000-000000000002');
reset role;

select is(
  (select status from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly' and (definition ->> 'stat') = 'FOR'),
  'completed', 'quête hebdo FOR: complétée après la dernière habitude requise'
);
select is(
  (select level from user_stats
   where user_id = 'ce900001-0000-0000-0000-000000000001' and stat = 'FOR'),
  2, 'récompense quête hebdo: +100 XP fait passer FOR au niveau 2 (10 propre + 100 bonus = 110)'
);
select is(
  (select current_xp from user_stats
   where user_id = 'ce900001-0000-0000-0000-000000000001' and stat = 'FOR'),
  10, 'récompense quête hebdo: reliquat 10 XP après le niveau 2 (110 - 100)'
);
select is(
  (select progress from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly' and (definition ->> 'stat') = 'INT'),
  0, 'quête hebdo INT: non affectée par une complétion FOR'
);

-- Une 2e habitude FOR complétée ne doit pas re-progresser la quête déjà
-- complétée (pas de double récompense).
select set_config(
  'request.jwt.claims',
  '{"sub":"ce900001-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select complete_habit('ce900003-0000-0000-0000-000000000003');
reset role;

select is(
  (select progress from quests
   where user_id = 'ce900001-0000-0000-0000-000000000001' and type = 'weekly' and (definition ->> 'stat') = 'FOR'),
  15, 'quête hebdo FOR: progression inchangée (déjà complétée, pas de double récompense)'
);

-- ============================================================================
-- Anti-triche : fonctions système + tables durcies réservées au serveur
-- ============================================================================
select set_config(
  'request.jwt.claims',
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$ select run_daily_tick() $$, '42501', null,
  'anti-triche: authenticated ne peut pas appeler run_daily_tick directement'
);
select throws_ok(
  $$ select run_weekly_tick() $$, '42501', null,
  'anti-triche: authenticated ne peut pas appeler run_weekly_tick directement'
);
select throws_ok(
  $$ select generate_weekly_quests('c1111111-1111-1111-1111-111111111111', current_date) $$, '42501', null,
  'anti-triche: authenticated ne peut pas appeler generate_weekly_quests directement'
);
select throws_ok(
  $$ select draw_daily_event('c1111111-1111-1111-1111-111111111111', current_date) $$, '42501', null,
  'anti-triche: authenticated ne peut pas appeler draw_daily_event directement'
);
select throws_ok(
  $$ select draw_secret_quest('c1111111-1111-1111-1111-111111111111', current_date) $$, '42501', null,
  'anti-triche: authenticated ne peut pas appeler draw_secret_quest directement'
);
select throws_ok(
  $$ insert into quests (user_id, type, target) values
     ('c1111111-1111-1111-1111-111111111111', 'weekly', 1) $$, '42501', null,
  'anti-triche: écriture directe dans quests refusée'
);
select throws_ok(
  $$ update boss_fights set hp = 0 where user_id = 'c3333333-3333-3333-3333-333333333333' $$,
  '42501', null,
  'anti-triche: écriture directe dans boss_fights refusée'
);
select throws_ok(
  $$ insert into user_titles (user_id, title_id) select
     'c1111111-1111-1111-1111-111111111111', id from titles limit 1 $$, '42501', null,
  'anti-triche: écriture directe dans user_titles refusée'
);
select throws_ok(
  $$ insert into notification_queue (user_id, trigger_type) values
     ('c1111111-1111-1111-1111-111111111111', 'boss_spawn') $$, '42501', null,
  'anti-triche: écriture directe dans notification_queue refusée'
);
select ok(
  (select count(*) from quests) >= 0,
  'RLS: lecture de ses propres quêtes autorisée (pas d''erreur)'
);
select ok(
  (select count(*) from notification_queue
   where user_id = 'c1111111-1111-1111-1111-111111111111') >= 1,
  'RLS: lecture de sa propre file de notifications autorisée'
);

reset role;
select * from finish();
rollback;
