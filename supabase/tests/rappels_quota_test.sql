-- ============================================================================
-- Rappels au rythme du quota
--
-- La règle à protéger avant toutes les autres : **dans les temps ⇒ SILENCE**.
-- Une notification qui arrive alors qu'on est à jour n'est plus un rappel,
-- c'est du bruit — et le bruit, on finit par le couper. Tout le reste de la
-- mécanique (escalade, plafonds) ne vaut rien si celle-là tombe.
--
-- La décision est testée en lui INJECTANT l'instant local : on ne va pas
-- attendre 13 h pour savoir si le créneau de 13 h s'ouvre.
-- ============================================================================
create extension if not exists pgtap;

begin;
select plan(19);

-- Lundi 2026-01-05 → dimanche 2026-01-11.
-- (2026-01-01 est un jeudi, donc le 5 est bien un lundi.)

-- ────────────────────────────────────────────────────────────────────────────
-- A — Les créneaux d'un quota journalier
-- ────────────────────────────────────────────────────────────────────────────
select is(quota_day_slot_hour(1, 1), 20, 'créneaux ×1 : un seul rappel, à 20 h');
select is(quota_day_slot_hour(3, 1), 13, 'créneaux ×3 : le premier à 13 h');
select is(quota_day_slot_hour(3, 2), 16, 'créneaux ×3 : le deuxième à 16 h');
select is(
  quota_day_slot_hour(3, 3), 20,
  'créneaux ×3 : le dernier à 20 h — avant le rituel du soir et la clôture'
);

-- ────────────────────────────────────────────────────────────────────────────
-- B — Quota JOURNALIER (« boire 3 verres d'eau », sans heure limite)
--     C'est précisément le cas que T-30/T-15 ne savait pas traiter.
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('4a000000-0000-0000-0000-00000000000a', 'jour@rq.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency,
                    deadline_time, created_at)
values ('4a000000-0000-0000-0000-0000000000aa',
        '4a000000-0000-0000-0000-00000000000a', 'eau', 'END', 'easy',
        'daily', 3, null, '2025-12-01');

select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 13:02'),
  1, '0 verre bu à 13 h → le créneau 1 s''ouvre'
);
select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 13:07'),
  null, 'hors de la fenêtre de 5 min → rien (le cron passe toutes les 5 min)'
);
select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 15:02'),
  null, '15 h n''est pas un créneau pour un quota ×3 (13 h, 16 h, 20 h)'
);

-- Il boit son premier verre → il est À JOUR pour le créneau 1.
insert into habit_logs (habit_id, user_id, date, completions, completed_at, xp_earned)
values ('4a000000-0000-0000-0000-0000000000aa',
        '4a000000-0000-0000-0000-00000000000a', '2026-01-05', 1, now(), 100);

select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 13:02'),
  null, '⭐ DANS LES TEMPS ⇒ SILENCE : 1 verre bu, le créneau 1 ne dit rien'
);
select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 16:02'),
  2, 'mais à 16 h il devrait en avoir 2 : le créneau 2 s''ouvre'
);

-- Il boit les deux suivants → quota rempli.
update habit_logs set completions = 3
  where habit_id = '4a000000-0000-0000-0000-0000000000aa' and date = '2026-01-05';

select is(
  quota_day_due_slot('4a000000-0000-0000-0000-0000000000aa', '2026-01-05 20:02'),
  null, '⭐ QUOTA REMPLI ⇒ SILENCE, même au dernier créneau'
);

-- ────────────────────────────────────────────────────────────────────────────
-- C — Quota HEBDO : le trou que M8 avait ouvert
--     « 3 séances cette semaine » pouvait se rater sans un seul rappel.
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('4b000000-0000-0000-0000-00000000000b', 'hebdo@rq.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency,
                    deadline_time, created_at)
values ('4b000000-0000-0000-0000-0000000000bb',
        '4b000000-0000-0000-0000-00000000000b', 'muscu', 'FOR', 'hard',
        'weekly', 3, null, '2025-12-01');

select is(
  quota_period_is_due('4b000000-0000-0000-0000-0000000000bb', '2026-01-08 19:02'),
  true, 'jeudi 19 h, 0 séance sur 3 : en retard sur le rythme → un rappel part'
);
select is(
  quota_period_is_due('4b000000-0000-0000-0000-0000000000bb', '2026-01-08 15:02'),
  false, 'un seul rendez-vous par jour : à 15 h, rien'
);

-- Il fait DEUX séances dès le mardi. Attendu le jeudi (4 jours sur 7) :
-- ceil(3 × 4/7) = 2. Il est donc PILE dans les temps.
insert into habit_logs (habit_id, user_id, date, completions, completed_at, xp_earned)
values ('4b000000-0000-0000-0000-0000000000bb',
        '4b000000-0000-0000-0000-00000000000b', '2026-01-06', 2, now(), 1000);

select is(
  quota_period_is_due('4b000000-0000-0000-0000-0000000000bb', '2026-01-08 19:02'),
  false,
  '⭐ DANS LE RYTHME ⇒ SILENCE : 2 séances faites, 2 attendues le jeudi'
);

-- Mais dimanche, il en faut 3. Il est en retard.
select is(
  quota_period_is_due('4b000000-0000-0000-0000-0000000000bb', '2026-01-11 19:02'),
  true, 'dimanche : 2 sur 3, la clôture arrive → le Système écrit'
);

-- Il fait la troisième → quota rempli.
update habit_logs set completions = 3
  where habit_id = '4b000000-0000-0000-0000-0000000000bb' and date = '2026-01-06';

select is(
  quota_period_is_due('4b000000-0000-0000-0000-0000000000bb', '2026-01-11 19:02'),
  false, '⭐ QUOTA REMPLI ⇒ SILENCE jusqu''à la semaine suivante'
);

-- Celui qui fait tout dès le lundi n'entend JAMAIS parler de rien de la semaine.
select is(
  (select bool_or(quota_period_is_due('4b000000-0000-0000-0000-0000000000bb',
                                      (d::date || ' 19:02')::timestamp))
     from generate_series('2026-01-05'::date, '2026-01-11'::date, interval '1 day') d),
  false,
  '⭐ quota rempli dès le lundi : ZÉRO rappel sur les 7 jours de la semaine'
);

-- ────────────────────────────────────────────────────────────────────────────
-- D — Une quête journalière AVEC heure limite garde T-30/T-15
--     (on ne casse pas ce qui marche, et surtout : pas de double voix)
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('4c000000-0000-0000-0000-00000000000c', 'deadline@rq.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, recurrence, frequency,
                    deadline_time, created_at)
values ('4c000000-0000-0000-0000-0000000000cc',
        '4c000000-0000-0000-0000-00000000000c', 'deep work', 'PRO', 'hard',
        'daily', 1, '20:00', '2025-12-01');

select is(
  quota_day_due_slot('4c000000-0000-0000-0000-0000000000cc', '2026-01-05 20:02'),
  null,
  'heure limite définie → AUCUN quota_day : une quête, une seule voix (T-30/T-15)'
);

-- ────────────────────────────────────────────────────────────────────────────
-- E — Les textes existent pour les deux nouveaux déclencheurs
-- ────────────────────────────────────────────────────────────────────────────
select ok(
  (select count(*) from notification_templates
   where trigger_type = 'quota_day' and active) >= 8,
  'textes : assez de variantes quota_day pour que l''anti-répétition respire'
);
select ok(
  (select count(*) from notification_templates
   where trigger_type = 'quota_period' and active) >= 6,
  'textes : assez de variantes quota_period'
);

select * from finish();
rollback;
