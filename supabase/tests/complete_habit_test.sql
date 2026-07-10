-- ============================================================================
-- LEVELUP — Test pgTAP : complete_habit() et durcissement RLS (M1)
-- Lancé par `supabase test db` (npm run test).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(16);

-- Fixture : un user, timezone fixe pour un calcul de "aujourd'hui" déterministe.
insert into auth.users (id, email, raw_user_meta_data)
values ('33333333-3333-3333-3333-333333333333', 'm1@test.dev',
        '{"timezone":"UTC"}'::jsonb);

-- --- Fonctions pures : formule de niveau et table de rang (verrouillées) ---
select is(xp_to_next_level(1), 100, 'xp_to_next_level(1) = 100');
select is(xp_to_next_level(2), 283, 'xp_to_next_level(2) = 283');
select is(xp_to_next_level(5), 1118, 'xp_to_next_level(5) = 1118');
select is(xp_to_next_level(10), 3162, 'xp_to_next_level(10) = 3162');

select is(rank_for_level(1), 'E'::hunter_rank, 'rang E pour niveau 1');
select is(rank_for_level(9), 'D'::hunter_rank, 'rang D pour niveau 9');
select is(rank_for_level(50), 'S'::hunter_rank, 'rang S pour niveau 50');

-- --- Contexte : bascule en utilisateur authentifié ---
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',
  true
);
set local role authenticated;

-- Habitude difficile (+50 XP), sans version minimale.
insert into habits (id, user_id, name, stat, difficulty)
values ('44444444-4444-4444-4444-444444444444',
        '33333333-3333-3333-3333-333333333333', 'muscu', 'FOR', 'hard');

-- 1er check-in : XP complet, pas de multiplicateur (streak = 1).
select results_eq(
  $$ select (complete_habit('44444444-4444-4444-4444-444444444444')->>'xp_earned')::int $$,
  $$ values (50) $$,
  'complete_habit: 50 XP pour une habitude "hard" au 1er jour'
);

-- 2e appel le même jour : idempotent, pas de double XP.
select results_eq(
  $$ select complete_habit('44444444-4444-4444-4444-444444444444')->>'already_completed' $$,
  $$ values ('true') $$,
  'complete_habit: idempotent (2e appel même jour)'
);

select is(
  (select current_xp from user_stats
   where user_id = '33333333-3333-3333-3333-333333333333' and stat = 'FOR'),
  50, 'user_stats.current_xp = 50 après un seul crédit (pas de double XP)'
);

-- Simule 20 jours de streak consécutifs (backdate) pour atteindre le palier
-- x1.2 au 21e jour, sans passer par 21 appels réels. Fixture = rôle
-- privilégié (le client n'a plus le droit d'écrire dans streaks — durci
-- plus bas dans ce même fichier).
reset role;
update streaks
  set current = 20, best = 20, last_completed_date = current_date - 1
  where user_id = '33333333-3333-3333-3333-333333333333'
    and habit_id = '44444444-4444-4444-4444-444444444444';
delete from habit_logs
  where habit_id = '44444444-4444-4444-4444-444444444444' and date = current_date;
set local role authenticated;

select results_eq(
  $$ select (complete_habit('44444444-4444-4444-4444-444444444444')->>'xp_earned')::int $$,
  $$ values (60) $$,
  'complete_habit: streak >= 21 -> x1.2 (50 * 1.2 = 60)'
);

-- Level-up : XP total sur FOR = 50 + 60 = 110 >= seuil niv1->2 (100).
select is(
  (select level from user_stats
   where user_id = '33333333-3333-3333-3333-333333333333' and stat = 'FOR'),
  2, 'level-up: niveau 2 atteint (110 XP >= seuil 100)'
);
select is(
  (select current_xp from user_stats
   where user_id = '33333333-3333-3333-3333-333333333333' and stat = 'FOR'),
  10, 'level-up: reliquat 10 XP après passage niveau 2 (110 - 100)'
);

-- --- Durcissement RLS : le client ne peut plus écrire directement ---
select throws_ok(
  $$ update user_stats set current_xp = 999999
     where user_id = '33333333-3333-3333-3333-333333333333' and stat = 'FOR' $$,
  '42501', null,
  'anti-triche: écriture directe sur user_stats refusée'
);

select throws_ok(
  $$ update profiles set rank = 'S'
     where id = '33333333-3333-3333-3333-333333333333' $$,
  '42501', null,
  'anti-triche: écriture directe sur profiles.rank refusée'
);

select throws_ok(
  $$ insert into habit_logs (habit_id, user_id, date, xp_earned)
     values ('44444444-4444-4444-4444-444444444444',
             '33333333-3333-3333-3333-333333333333', current_date + 1, 999) $$,
  '42501', null,
  'anti-triche: insertion directe dans habit_logs refusée'
);

reset role;
select * from finish();
rollback;
