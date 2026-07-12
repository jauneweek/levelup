-- ============================================================================
-- LEVELUP — Test pgTAP : Identité (M6) — Armée des Ombres, bonus passif,
-- Journal du Chasseur. Lancé par `supabase test db` (npm run test).
-- Dates fixes pour close_day()/generate_weekly_journal() ; date réelle pour
-- complete_habit() (comme les tests précédents).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(27);

-- ============================================================================
-- Scénario A — Extraction et évolution de grade d'une Ombre (§3.11)
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('ea111111-1111-1111-1111-111111111111', 'a@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('ea222222-2222-2222-2222-222222222222',
        'ea111111-1111-1111-1111-111111111111', 'Méditation quotidienne', 'SAG', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2019-01-01');

-- 99 complétions : pas encore d'Ombre.
do $$
declare d date;
begin
  for d in select generate_series('2020-01-01'::date, '2020-04-08'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('ea222222-2222-2222-2222-222222222222',
            'ea111111-1111-1111-1111-111111111111', d, d::timestamptz + interval '12 hours', 10, 1.0);
  end loop;
end $$;

select is(
  (select count(*)::int from habit_logs
   where habit_id = 'ea222222-2222-2222-2222-222222222222' and completed_at is not null),
  99, 'sanity: 99 complétions enregistrées'
);

select check_shadow_extraction(
  'ea111111-1111-1111-1111-111111111111', 'ea222222-2222-2222-2222-222222222222'
);
select is(
  (select count(*)::int from shadows where habit_id = 'ea222222-2222-2222-2222-222222222222'),
  0, 'pas d''Ombre avant le seuil des 100 complétions'
);

-- 100e complétion : extraction en Soldat.
insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
values ('ea222222-2222-2222-2222-222222222222',
        'ea111111-1111-1111-1111-111111111111', '2020-04-09', '2020-04-09 12:00:00+00', 10, 1.0);
select check_shadow_extraction(
  'ea111111-1111-1111-1111-111111111111', 'ea222222-2222-2222-2222-222222222222'
);

select is(
  (select grade from shadows where habit_id = 'ea222222-2222-2222-2222-222222222222'),
  'soldat'::shadow_grade, 'Ombre extraite en Soldat à 100 complétions'
);
select is(
  (select completions_at_extraction from shadows
   where habit_id = 'ea222222-2222-2222-2222-222222222222'),
  100, 'completions_at_extraction = 100'
);

-- 150 complétions de plus (total 250) : évolution en Chevalier, même Ombre.
do $$
declare d date;
begin
  for d in select generate_series('2020-04-10'::date, '2020-09-06'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('ea222222-2222-2222-2222-222222222222',
            'ea111111-1111-1111-1111-111111111111', d, d::timestamptz + interval '12 hours', 10, 1.0);
  end loop;
end $$;
select check_shadow_extraction(
  'ea111111-1111-1111-1111-111111111111', 'ea222222-2222-2222-2222-222222222222'
);

select is(
  (select count(*)::int from shadows where habit_id = 'ea222222-2222-2222-2222-222222222222'),
  1, 'toujours une seule Ombre par habitude (évolution, pas duplication)'
);
select is(
  (select grade from shadows where habit_id = 'ea222222-2222-2222-2222-222222222222'),
  'chevalier'::shadow_grade, 'Ombre évoluée en Chevalier à 250 complétions'
);

-- ============================================================================
-- Scénario B — Bonus XP passif des Ombres (§3.11), hors du cap x3 (M6)
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('eb111111-1111-1111-1111-111111111111', 'b@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule)
values
  ('eb222221-2222-2222-2222-222222222221', 'eb111111-1111-1111-1111-111111111111', 'h1', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222222-2222-2222-2222-222222222222', 'eb111111-1111-1111-1111-111111111111', 'h2', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222223-2222-2222-2222-222222222223', 'eb111111-1111-1111-1111-111111111111', 'h3', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222224-2222-2222-2222-222222222224', 'eb111111-1111-1111-1111-111111111111', 'h4', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222225-2222-2222-2222-222222222225', 'eb111111-1111-1111-1111-111111111111', 'h5', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222226-2222-2222-2222-222222222226', 'eb111111-1111-1111-1111-111111111111', 'h6', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb),
  ('eb222227-2222-2222-2222-222222222227', 'eb111111-1111-1111-1111-111111111111', 'cible', 'FOR', 'easy', '{"days":[1,2,3,4,5,6,7]}'::jsonb);

-- 3 Ombres (fixtures directes, hors mécanisme d'extraction) -> +6%.
insert into shadows (user_id, habit_id, name, grade, completions_at_extraction)
values
  ('eb111111-1111-1111-1111-111111111111', 'eb222221-2222-2222-2222-222222222221', 'h1', 'soldat', 100),
  ('eb111111-1111-1111-1111-111111111111', 'eb222222-2222-2222-2222-222222222222', 'h2', 'soldat', 100),
  ('eb111111-1111-1111-1111-111111111111', 'eb222223-2222-2222-2222-222222222223', 'h3', 'soldat', 100);

select is(
  shadow_xp_bonus_multiplier('eb111111-1111-1111-1111-111111111111', 'FOR'),
  1.06::numeric, 'bonus Ombres: 3 Ombres -> +6% (1.06)'
);

-- 2 Ombres de plus (total 5) -> +10%, plafond atteint pile.
insert into shadows (user_id, habit_id, name, grade, completions_at_extraction)
values
  ('eb111111-1111-1111-1111-111111111111', 'eb222224-2222-2222-2222-222222222224', 'h4', 'soldat', 100),
  ('eb111111-1111-1111-1111-111111111111', 'eb222225-2222-2222-2222-222222222225', 'h5', 'soldat', 100);

select is(
  shadow_xp_bonus_multiplier('eb111111-1111-1111-1111-111111111111', 'FOR'),
  1.10::numeric, 'bonus Ombres: 5 Ombres -> +10% (plafond)'
);

-- 6e Ombre : toujours plafonné à +10%.
insert into shadows (user_id, habit_id, name, grade, completions_at_extraction)
values ('eb111111-1111-1111-1111-111111111111', 'eb222226-2222-2222-2222-222222222226', 'h6', 'soldat', 100);

select is(
  shadow_xp_bonus_multiplier('eb111111-1111-1111-1111-111111111111', 'FOR'),
  1.10::numeric, 'bonus Ombres: 6e Ombre ne dépasse pas le plafond de +10%'
);

-- Application réelle : complete_habit sur une habitude FOR neuve bénéficie
-- du bonus de +10% (couche séparée du cap x3, appliquée en plus).
select set_config(
  'request.jwt.claims',
  '{"sub":"eb111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select results_eq(
  $$ select (j->>'xp_earned')::int, (j->>'shadow_bonus')::numeric
     from (select complete_habit('eb222227-2222-2222-2222-222222222227') as j) s $$,
  $$ values (11, 1.10::numeric) $$,
  'complete_habit: 10 XP * bonus Ombres 1.10 = 11, hors du cap x3'
);

reset role;

-- ============================================================================
-- Scénario C — Journal du Chasseur (§3.15) : génération hebdomadaire
-- ============================================================================
insert into auth.users (id, email, raw_user_meta_data)
values ('ec111111-1111-1111-1111-111111111111', 'c@test.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (id, user_id, name, stat, difficulty, schedule, created_at)
values ('ec222222-2222-2222-2222-222222222222',
        'ec111111-1111-1111-1111-111111111111', 'quête C', 'FOR', 'easy',
        '{"days":[1,2,3,4,5,6,7]}'::jsonb, '2025-01-01');

-- 22 journées parfaites (2026-01-18 .. 2026-02-08) : démarrées assez tôt
-- pour que le taux glissant 7j des deux bornes de comparaison (samedi de
-- chaque semaine) soit à 100% sans trou d'historique. Le streak franchit le
-- palier des 21 jours (titre "Régulier") pile le 02-07, dans la semaine 2
-- (lundi 02-02 au dimanche 02-08) — vérifie au passage le correctif
-- unlocked_at=p_date (section 3 de la migration).
do $$
declare d date;
begin
  for d in select generate_series('2026-01-18'::date, '2026-02-08'::date, interval '1 day')::date
  loop
    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier)
    values ('ec222222-2222-2222-2222-222222222222',
            'ec111111-1111-1111-1111-111111111111', d, d::timestamptz + interval '12 hours', 10, 1.0);
    perform close_day('ec111111-1111-1111-1111-111111111111', d);
  end loop;
end $$;

select is(
  (select count(*)::int from user_titles ut join titles t on t.id = ut.title_id
   where ut.user_id = 'ec111111-1111-1111-1111-111111111111' and t.name = 'Régulier'
     and ut.unlocked_at::date = '2026-02-07'),
  1, 'sanity: titre "Régulier" débloqué le 2026-02-07 (semaine 2, unlocked_at = p_date)'
);

-- Fixtures directes pour Ombre extraite + dégâts boss durant la semaine 2.
insert into shadows (user_id, habit_id, name, grade, completions_at_extraction, extracted_at)
values ('ec111111-1111-1111-1111-111111111111', 'ec222222-2222-2222-2222-222222222222',
        'quête C', 'soldat', 100, '2026-02-03 10:00:00+00');

insert into notification_queue (user_id, trigger_type, vars, created_at)
values ('ec111111-1111-1111-1111-111111111111', 'boss_damage', '{}'::jsonb, '2026-02-04 08:00:00+00');

select generate_weekly_journal('ec111111-1111-1111-1111-111111111111', '2026-02-02');

select is(
  (select (payload ->> 'quests_completed')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  7, 'journal: 7 quêtes complétées cette semaine (1/jour)'
);
select is(
  (select (payload ->> 'xp_gained')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  70, 'journal: 70 XP gagnés cette semaine (7 * 10)'
);
select is(
  (select (payload ->> 'xp_lost')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  0, 'journal: 0 XP perdu (aucune pénalité cette semaine)'
);
select is(
  (select (payload ->> 'boss_damage')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1, 'journal: 1 dégât infligé au boss cette semaine'
);
select is(
  (select (payload ->> 'shadows_extracted')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1, 'journal: 1 Ombre extraite cette semaine'
);
select is(
  (select (payload ->> 'titles_unlocked')::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1, 'journal: 1 titre débloqué cette semaine'
);
select is(
  (select (payload ->> 'completion_rate')::numeric from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1.0::numeric, 'journal: taux de complétion 100% (toutes les journées parfaites)'
);
select is(
  (select (payload ->> 'completion_rate_prev')::numeric from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1.0::numeric, 'journal: taux de la semaine précédente aussi 100%'
);
select is(
  (select payload ->> 'ghost_delta' from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  null, 'journal: pas de Fantôme (compte trop récent, aucun snapshot à J-30)'
);
select is(
  (select count(*)::int from journal_entries je,
     jsonb_object_keys(je.payload -> 'daily_breakdown') k
   where je.user_id = 'ec111111-1111-1111-1111-111111111111' and je.week_start = '2026-02-02'),
  7, 'journal: répartition quotidienne sur les 7 jours de la semaine'
);

-- Idempotence : rejouer ne crée pas une 2e entrée.
select generate_weekly_journal('ec111111-1111-1111-1111-111111111111', '2026-02-02');
select is(
  (select count(*)::int from journal_entries
   where user_id = 'ec111111-1111-1111-1111-111111111111' and week_start = '2026-02-02'),
  1, 'journal: idempotent (pas de doublon si rejoué)'
);

-- ============================================================================
-- Anti-triche : fonctions système + tables réservées au serveur
-- ============================================================================
select set_config(
  'request.jwt.claims',
  '{"sub":"ea111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$ select check_shadow_extraction(
       'ea111111-1111-1111-1111-111111111111', 'ea222222-2222-2222-2222-222222222222') $$,
  '42501', null,
  'anti-triche: authenticated ne peut pas appeler check_shadow_extraction directement'
);
select throws_ok(
  $$ select shadow_xp_bonus_multiplier('ea111111-1111-1111-1111-111111111111', 'FOR') $$,
  '42501', null,
  'anti-triche: authenticated ne peut pas appeler shadow_xp_bonus_multiplier directement'
);
select throws_ok(
  $$ select generate_weekly_journal('ea111111-1111-1111-1111-111111111111', current_date) $$,
  '42501', null,
  'anti-triche: authenticated ne peut pas appeler generate_weekly_journal directement'
);
select throws_ok(
  $$ insert into shadows (user_id, habit_id, name, grade, completions_at_extraction) values
     ('ea111111-1111-1111-1111-111111111111', 'ea222222-2222-2222-2222-222222222222', 'triche', 'marechal', 1000) $$,
  '42501', null,
  'anti-triche: écriture directe dans shadows refusée'
);
select throws_ok(
  $$ insert into journal_entries (user_id, week_start, payload) values
     ('ea111111-1111-1111-1111-111111111111', current_date, '{}'::jsonb) $$,
  '42501', null,
  'anti-triche: écriture directe dans journal_entries refusée'
);

reset role;
select * from finish();
rollback;
