-- ============================================================================
-- M8 — Planification par quota (SPEC §3.5.1 → §3.5.3)
--
-- Ce que ces tests protègent, dans l'ordre d'importance :
--   1. la journée NEUTRE (sans elle, « aucune quête aujourd'hui » = streak gratuit)
--   2. l'idempotence de la clôture de période (un cron rejoué ne double pas la peine)
--   3. le quota > 1 (le streak ne doit pas monter 3× en une journée)
-- ============================================================================
begin;
select plan(24);

-- Semaine de référence : lundi 2026-01-05 → dimanche 2026-01-11.
-- (Vérifié : 2026-01-01 est un jeudi.)

-- ────────────────────────────────────────────────────────────────────────────
-- A — Quota JOURNALIER > 1 : « boire 3 verres d'eau » se valide trois fois
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8a00000-0000-0000-0000-00000000000a', 'a@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('d8a00000-0000-0000-0000-0000000000aa',
        'd8a00000-0000-0000-0000-00000000000a', 'eau', 'END', 'easy',
        'daily', 3, now() - interval '10 days');

select is(
  habit_remaining('d8a00000-0000-0000-0000-0000000000aa', current_date),
  3, 'quota journalier x3 : 3 complétions restantes à la création'
);

select set_config('request.jwt.claims',
  '{"sub":"d8a00000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select complete_habit('d8a00000-0000-0000-0000-0000000000aa');
reset role;

select is(
  habit_remaining('d8a00000-0000-0000-0000-0000000000aa', current_date),
  2, 'quota x3 : il en reste 2 après la 1re complétion'
);

select set_config('request.jwt.claims',
  '{"sub":"d8a00000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select complete_habit('d8a00000-0000-0000-0000-0000000000aa');
select complete_habit('d8a00000-0000-0000-0000-0000000000aa');
reset role;

select is(
  habit_remaining('d8a00000-0000-0000-0000-0000000000aa', current_date),
  0, 'quota x3 : quota rempli après 3 complétions'
);

-- UNIQUE(habit_id, date) est conservé : les complétions s'accumulent DANS la
-- ligne du jour, elles n'en créent pas de nouvelles (idempotence des crons).
select is(
  (select count(*)::int from habit_logs
   where habit_id = 'd8a00000-0000-0000-0000-0000000000aa' and date = current_date),
  1, 'quota x3 : une seule ligne de journal pour la journée'
);
select is(
  (select completions from habit_logs
   where habit_id = 'd8a00000-0000-0000-0000-0000000000aa' and date = current_date),
  3, 'quota x3 : le compteur de la ligne vaut 3'
);

select set_config('request.jwt.claims',
  '{"sub":"d8a00000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is(
  (complete_habit('d8a00000-0000-0000-0000-0000000000aa') ->> 'quota_filled')::boolean,
  true, 'quota x3 : la 4e complétion est refusée (quota rempli)'
);
reset role;

-- Le garde le plus subtil du milestone : sans lui, un quota x3 ferait grimper
-- le streak de 3 en une seule journée — et close_day le remettrait à 0 le soir.
select is(
  (select current from streaks
   where habit_id = 'd8a00000-0000-0000-0000-0000000000aa'),
  1, 'quota x3 : le streak de l''habitude avance d''UN seul cran, pas de trois'
);

-- ────────────────────────────────────────────────────────────────────────────
-- B — JOURNÉE NEUTRE (§3.5.3) : rien à faire ⇒ ni parfaite, ni ratée
--     Sans ce garde, `done >= due` serait vrai (0 >= 0) et une journée sans la
--     moindre quête offrirait un streak gratuit — la faille que le quota ouvre.
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8b00000-0000-0000-0000-00000000000b', 'b@quota.dev', '{"timezone":"UTC"}'::jsonb);

update streaks set current = 5, best = 9, shields = 2
  where user_id = 'd8b00000-0000-0000-0000-00000000000b' and habit_id is null;

select is(
  (select due from day_obligation('d8b00000-0000-0000-0000-00000000000b', current_date)),
  0, 'journée neutre : aucune obligation (ni quota journalier, ni todo)'
);

select is(
  (close_day('d8b00000-0000-0000-0000-00000000000b', current_date) ->> 'is_neutral_day')::boolean,
  true, 'journée neutre : détectée'
);
select is(
  (select (payload ->> 'is_perfect_day')::boolean from (
     select close_day('d8b00000-0000-0000-0000-00000000000b', current_date - 1) as payload
   ) s),
  false, 'journée neutre : JAMAIS comptée comme parfaite'
);
select is(
  (select current from streaks
   where user_id = 'd8b00000-0000-0000-0000-00000000000b' and habit_id is null),
  5, 'journée neutre : le streak global est gelé (ni +1, ni reset)'
);
select is(
  (select shields from streaks
   where user_id = 'd8b00000-0000-0000-0000-00000000000b' and habit_id is null),
  2, 'journée neutre : aucun bouclier consommé'
);

-- ────────────────────────────────────────────────────────────────────────────
-- C — Quota HEBDOMADAIRE : dû aucun jour précis, jugé à la clôture
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8c00000-0000-0000-0000-00000000000c', 'c@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('d8c00000-0000-0000-0000-0000000000cc',
        'd8c00000-0000-0000-0000-00000000000c', 'muscu', 'FOR', 'hard',
        'weekly', 3, '2025-12-01');

update user_stats set current_xp = 1000
  where user_id = 'd8c00000-0000-0000-0000-00000000000c' and stat = 'FOR';

-- Une seule séance faite dans la semaine, le mercredi.
insert into habit_logs (habit_id, user_id, date, completions, completed_at, xp_earned)
values ('d8c00000-0000-0000-0000-0000000000cc',
        'd8c00000-0000-0000-0000-00000000000c', '2026-01-07', 1, now(), 50);

select is(
  habit_remaining('d8c00000-0000-0000-0000-0000000000cc', '2026-01-08'),
  2, 'quota hebdo x3 : 2 séances restent dues dans la semaine'
);
select is(
  (select due from day_obligation('d8c00000-0000-0000-0000-00000000000c', '2026-01-08')),
  0, 'quota hebdo : n''est dû AUCUN jour précis (rien dans le dû du jeudi)'
);

-- Jeudi : ce n'est pas la fin de la semaine, rien n'est jugé.
select close_day('d8c00000-0000-0000-0000-00000000000c', '2026-01-08');
select is(
  (select count(*)::int from period_closures
   where habit_id = 'd8c00000-0000-0000-0000-0000000000cc'),
  0, 'quota hebdo : aucun jugement un jeudi (la période n''est pas close)'
);

-- Dimanche : fin de période → jugement.
select close_day('d8c00000-0000-0000-0000-00000000000c', '2026-01-11');
select is(
  (select missing from period_closures
   where habit_id = 'd8c00000-0000-0000-0000-0000000000cc'),
  2, 'clôture hebdo : manquant = 3 - 1 = 2'
);
select is(
  (select current_xp from user_stats
   where user_id = 'd8c00000-0000-0000-0000-00000000000c' and stat = 'FOR'),
  960, 'clôture hebdo : pénalité = 50 * 0.4 * 2 manquants = 40 (1000 -> 960)'
);

-- Idempotence RÉELLE : on retire le verrou du snapshot pour forcer close_day à
-- rejouer la même journée. Seul `period_closures` doit alors empêcher la
-- double peine.
delete from daily_snapshots
  where user_id = 'd8c00000-0000-0000-0000-00000000000c' and date = '2026-01-11';
select close_day('d8c00000-0000-0000-0000-00000000000c', '2026-01-11');
select is(
  (select current_xp from user_stats
   where user_id = 'd8c00000-0000-0000-0000-00000000000c' and stat = 'FOR'),
  960, 'clôture hebdo rejouée : la pénalité n''est PAS appliquée deux fois'
);

-- ────────────────────────────────────────────────────────────────────────────
-- D — Quête créée en cours de période : on ne reproche pas l'intenable
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8d00000-0000-0000-0000-00000000000d', 'd@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('d8d00000-0000-0000-0000-0000000000dd',
        'd8d00000-0000-0000-0000-00000000000d', 'tardive', 'INT', 'hard',
        'weekly', 2, '2026-01-08');          -- créée le jeudi, période ouverte le lundi

select close_day('d8d00000-0000-0000-0000-00000000000d', '2026-01-11');
select is(
  (select count(*)::int from period_closures
   where habit_id = 'd8d00000-0000-0000-0000-0000000000dd'),
  0, 'quête créée en cours de période : échappe au jugement de CETTE période'
);

-- ────────────────────────────────────────────────────────────────────────────
-- E — `once` et `temporary`
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8e00000-0000-0000-0000-00000000000e', 'e@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values
  ('d8e00000-0000-0000-0000-0000000000e1',
   'd8e00000-0000-0000-0000-00000000000e', 'passer le permis', 'PRO', 'hard',
   'once', 1, now() - interval '5 days'),
  ('d8e00000-0000-0000-0000-0000000000e2',
   'd8e00000-0000-0000-0000-00000000000e', 'défi du mois', 'SAG', 'easy',
   'weekly', 1, '2025-12-01');

update habits set temporary = true
  where id = 'd8e00000-0000-0000-0000-0000000000e2';

select is(
  habit_remaining('d8e00000-0000-0000-0000-0000000000e1', current_date),
  1, 'once : proposable tant qu''elle n''est pas faite'
);

select set_config('request.jwt.claims',
  '{"sub":"d8e00000-0000-0000-0000-00000000000e","role":"authenticated"}', true);
set local role authenticated;
select complete_habit('d8e00000-0000-0000-0000-0000000000e1');
reset role;

select is(
  habit_remaining('d8e00000-0000-0000-0000-0000000000e1', current_date + 400),
  0, 'once : ne revient JAMAIS, même l''année suivante'
);

select close_day('d8e00000-0000-0000-0000-00000000000e', '2026-01-11');
select is(
  (select active from habits where id = 'd8e00000-0000-0000-0000-0000000000e2'),
  false, 'temporary : archivée à la fin de sa période'
);

-- ────────────────────────────────────────────────────────────────────────────
-- F — Pénalité journalière PROPORTIONNELLE au manquant (§3.5.2)
--     Un « daily x3 » fait une seule fois coûte deux manquants, pas un.
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8f00000-0000-0000-0000-00000000000f', 'f@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('d8f00000-0000-0000-0000-0000000000ff',
        'd8f00000-0000-0000-0000-00000000000f', 'séries', 'FOR', 'hard',
        'daily', 3, now() - interval '30 days');

-- XP de départ basse À DESSEIN : à 1000 XP, les 50 gagnés déclencheraient la
-- boucle de montée de niveau (seuil 100 puis 283…), qui consomme l'XP et rendrait
-- le calcul de la pénalité illisible. Ici 40 + 50 = 90 < 100 : aucun niveau ne
-- passe, et il ne reste que ce qu'on veut mesurer.
update user_stats set current_xp = 40
  where user_id = 'd8f00000-0000-0000-0000-00000000000f' and stat = 'FOR';

-- 6 journées pleines derrière soi : on teste la pénalité, pas le mode slump
-- (qui désactiverait le multiplicateur et brouillerait la lecture).
insert into habit_logs (habit_id, user_id, date, completions, completed_at, xp_earned)
select 'd8f00000-0000-0000-0000-0000000000ff',
       'd8f00000-0000-0000-0000-00000000000f',
       (current_date - g)::date, 3, now(), 150
from generate_series(1, 6) as g;

select set_config('request.jwt.claims',
  '{"sub":"d8f00000-0000-0000-0000-00000000000f","role":"authenticated"}', true);
set local role authenticated;
select complete_habit('d8f00000-0000-0000-0000-0000000000ff');   -- 1 sur 3 : +50 XP
reset role;

select close_day('d8f00000-0000-0000-0000-00000000000f', current_date);
select is(
  (select current_xp from user_stats
   where user_id = 'd8f00000-0000-0000-0000-00000000000f' and stat = 'FOR'),
  50, 'pénalité journalière : 40 + 50 gagnés - (50 * 0.4 * 2 manquants) = 50'
);

-- ────────────────────────────────────────────────────────────────────────────
-- G — Deux quotas hebdo, dont un DÉJÀ jugé : pas de double peine sur l'autre
--     (garde le piège plpgsql : `returning ... into` ne remet PAS la variable
--     à null quand `on conflict do nothing` avale la ligne)
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('d8909000-0000-0000-0000-000000000090', 'g@quota.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency, created_at)
values
  ('d8909000-0000-0000-0000-000000000091',
   'd8909000-0000-0000-0000-000000000090', 'hebdo A', 'FOR', 'hard',
   'weekly', 2, '2025-12-01 08:00'),                       -- traitée en 1er
  ('d8909000-0000-0000-0000-000000000092',
   'd8909000-0000-0000-0000-000000000090', 'hebdo B', 'FOR', 'hard',
   'weekly', 2, '2025-12-01 09:00');                       -- traitée en 2e

update user_stats set current_xp = 1000
  where user_id = 'd8909000-0000-0000-0000-000000000090' and stat = 'FOR';

-- B a déjà été jugée (rattrapage partiel, cron interrompu…) : elle ne doit plus
-- rien coûter. A, elle, n'a jamais été jugée : elle coûte 40.
insert into period_closures (user_id, habit_id, recurrence, period_start, period_end,
                            quota, completed, missing, xp_penalty)
values ('d8909000-0000-0000-0000-000000000090',
        'd8909000-0000-0000-0000-000000000092', 'weekly',
        '2026-01-05', '2026-01-11', 2, 0, 2, 40);

select close_day('d8909000-0000-0000-0000-000000000090', '2026-01-11');
select is(
  (select current_xp from user_stats
   where user_id = 'd8909000-0000-0000-0000-000000000090' and stat = 'FOR'),
  960, 'clôture : seule la période NON jugée est pénalisée (1000 - 40, pas - 80)'
);

select * from finish();
rollback;
