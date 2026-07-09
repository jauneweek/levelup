-- ============================================================================
-- LEVELUP — Test pgTAP : trigger d'inscription + policies RLS
-- Lancé par `supabase test db` (npm run test).
-- Isolé (filtre par ids de test) et re-exécutable (begin/rollback).
-- ============================================================================
begin;
create extension if not exists pgtap;

select plan(9);

-- Ids de test déterministes
-- u1 = 11111111-…  /  u2 = 22222222-…

-- Fixtures : deux utilisateurs. Le trigger on_auth_user_created doit créer
-- profil + 5 stats + streak global pour chacun.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'u1@test.dev',
   '{"timezone":"Europe/Paris"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'u2@test.dev', '{}'::jsonb);

-- Une ligne de catalogue pour tester la lecture RLS (indépendant du seed).
insert into notification_templates (persona, tone, trigger_type, template)
values ('system', 'neutral', 't30', 'ping');

-- 1. Le trigger a créé les 2 profils
select is(
  (select count(*)::int from profiles
   where id in ('11111111-1111-1111-1111-111111111111',
                '22222222-2222-2222-2222-222222222222')),
  2, 'trigger: 2 profils créés à l''inscription'
);

-- 2. u1 possède exactement 5 statistiques
select is(
  (select count(*)::int from user_stats
   where user_id = '11111111-1111-1111-1111-111111111111'),
  5, 'trigger: 5 stats pour u1'
);

-- 3. La timezone provient des metadata d'inscription
select is(
  (select timezone from profiles
   where id = '11111111-1111-1111-1111-111111111111'),
  'Europe/Paris', 'trigger: timezone lue depuis raw_user_meta_data'
);

-- 4. Un streak global (habit_id NULL) a été créé pour u1
select is(
  (select count(*)::int from streaks
   where user_id = '11111111-1111-1111-1111-111111111111'
     and habit_id is null),
  1, 'trigger: streak global unique'
);

-- --- Bascule en contexte utilisateur authentifié = u1 ---
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);
set local role authenticated;

-- 5. RLS : u1 ne voit que ses propres stats (5), pas celles de u2
select is(
  (select count(*)::int from user_stats),
  5, 'RLS: u1 ne voit que ses 5 stats'
);

-- 6. RLS : u1 ne voit que son propre profil
select is(
  (select count(*)::int from profiles),
  1, 'RLS: u1 ne voit que son profil'
);

-- 7. RLS : le catalogue de templates est lisible par un authentifié
select ok(
  (select count(*) from notification_templates) >= 1,
  'RLS: catalogue notification_templates lisible'
);

-- 8. RLS : u1 ne peut PAS créer une habitude au nom de u2 (WITH CHECK)
select throws_ok(
  $$ insert into habits (user_id, name, stat, difficulty)
     values ('22222222-2222-2222-2222-222222222222', 'triche', 'FOR', 'easy') $$,
  '42501', null,
  'RLS: u1 ne peut pas écrire pour u2'
);

-- 9. RLS : u1 peut créer sa propre habitude
select lives_ok(
  $$ insert into habits (user_id, name, stat, difficulty)
     values ('11111111-1111-1111-1111-111111111111', 'pompes', 'FOR', 'easy') $$,
  'RLS: u1 peut créer sa propre habitude'
);

reset role;
select * from finish();
rollback;
