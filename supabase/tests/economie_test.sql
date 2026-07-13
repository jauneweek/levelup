-- ============================================================================
-- ÉCONOMIE — XP, Niveau du Chasseur, Rangs
--
-- Ce que ces tests verrouillent, par ordre d'importance :
--   1. L'INDÉPENDANCE AU VOLUME. Trois quêtes ou dix, une journée pleine vaut
--      1000 points. Sans ça, le rang récompenserait la quantité et non la
--      discipline — et « Monarque en 9,5 mois » ne voudrait rien dire.
--   2. Les pénalités ne touchent JAMAIS la piste du Chasseur (SPEC §8).
--   3. La première quête fait monter de niveau (le grief d'origine).
-- ============================================================================
create extension if not exists pgtap;

begin;
select plan(24);

-- ────────────────────────────────────────────────────────────────────────────
-- A — L'échelle et la courbe
-- ────────────────────────────────────────────────────────────────────────────
select is(base_xp('easy'),   100, 'XP de base : facile = 100');
select is(base_xp('medium'), 250, 'XP de base : moyenne = 250');
select is(base_xp('hard'),   500, 'XP de base : difficile = 500');

select is(
  hunter_xp_to_next(1), 100,
  'courbe : le 1er niveau coûte 100 XP — une seule quête facile suffit'
);
select is(
  hunter_xp_to_next(599), 877,
  'courbe : le dernier niveau avant Monarque coûte 877 XP'
);

-- La promesse chiffrée. Si ce test tombe, c'est que le rythme a dérivé.
select ok(
  (select sum(hunter_xp_to_next(l)) from generate_series(1, 599) l) between 285000 and 300000,
  'promesse : ~293 000 XP jusqu''à Monarque, soit ~9,5 mois à 1000 XP/jour'
);

-- ────────────────────────────────────────────────────────────────────────────
-- B — Les rangs : 100 niveaux chacun, le compteur repart à 1
-- ────────────────────────────────────────────────────────────────────────────
select is(rank_for_hunter_level(1),   'E'::hunter_rank, 'rang : niveau 1 → E');
select is(rank_for_hunter_level(100), 'E'::hunter_rank, 'rang : niveau 100 → encore E');
select is(rank_for_hunter_level(101), 'D'::hunter_rank, 'rang : niveau 101 → D (promotion)');
select is(rank_for_hunter_level(600), 'S'::hunter_rank, 'rang : niveau 600 → S');
select is(rank_for_hunter_level(601), 'M'::hunter_rank, 'rang : niveau 601 → Monarque');

select is(hunter_level_in_rank(100), 100, 'affichage : niveau 100 du rang E');
select is(
  hunter_level_in_rank(101), 1,
  'affichage : au passage de rang, le compteur repart à 1 — promotion, pas perte'
);

-- ────────────────────────────────────────────────────────────────────────────
-- C — LE CŒUR : le rang est indépendant du VOLUME
--
--     Trois chasseurs, trois volumes incomparables. Tous font une journée
--     PLEINE. Tous doivent gagner ~1000 XP de Chasseur — mais des radars très
--     différents. Le rang mesure la discipline ; le radar mesure la capacité.
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data) values
  ('ec000000-0000-0000-0000-00000000000a', 'petit@eco.dev', '{"timezone":"UTC"}'::jsonb),
  ('ec000000-0000-0000-0000-00000000000b', 'moyen@eco.dev', '{"timezone":"UTC"}'::jsonb),
  ('ec000000-0000-0000-0000-00000000000c', 'gros@eco.dev',  '{"timezone":"UTC"}'::jsonb);

-- Petit : 3 quêtes faciles par jour.
insert into habits (user_id, name, stat, difficulty, recurrence, frequency)
select 'ec000000-0000-0000-0000-00000000000a', 'p' || g, 'FOR', 'easy', 'daily', 1
from generate_series(1, 3) g;

-- Moyen : 4 quêtes mélangées.
insert into habits (user_id, name, stat, difficulty, recurrence, frequency) values
  ('ec000000-0000-0000-0000-00000000000b', 'm1', 'FOR', 'easy',   'daily', 1),
  ('ec000000-0000-0000-0000-00000000000b', 'm2', 'INT', 'medium', 'daily', 1),
  ('ec000000-0000-0000-0000-00000000000b', 'm3', 'SAG', 'hard',   'daily', 1),
  ('ec000000-0000-0000-0000-00000000000b', 'm4', 'PRO', 'medium', 'daily', 1);

-- Gros : 10 quêtes difficiles par jour.
insert into habits (user_id, name, stat, difficulty, recurrence, frequency)
select 'ec000000-0000-0000-0000-00000000000c', 'g' || g, 'FOR', 'hard', 'daily', 1
from generate_series(1, 10) g;

do $$
declare u uuid; h record; i int;
begin
  foreach u in array array['ec000000-0000-0000-0000-00000000000a'::uuid,
                           'ec000000-0000-0000-0000-00000000000b'::uuid,
                           'ec000000-0000-0000-0000-00000000000c'::uuid] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', u, 'role', 'authenticated')::text, true);
    for h in select id, frequency from habits where user_id = u loop
      for i in 1..h.frequency loop
        perform public.complete_habit(h.id);
      end loop;
    end loop;
  end loop;
end $$;

select ok(
  (select hunter_xp_total from profiles where id = 'ec000000-0000-0000-0000-00000000000a')
    between 990 and 1010,
  'volume : 3 quêtes faciles, journée pleine → ~1000 XP de Chasseur'
);
select ok(
  (select hunter_xp_total from profiles where id = 'ec000000-0000-0000-0000-00000000000b')
    between 990 and 1010,
  'volume : 4 quêtes mélangées, journée pleine → ~1000 XP de Chasseur (le MÊME)'
);
select ok(
  (select hunter_xp_total from profiles where id = 'ec000000-0000-0000-0000-00000000000c')
    between 990 and 1010,
  'volume : 10 quêtes difficiles, journée pleine → ~1000 XP de Chasseur (le MÊME)'
);

-- Le pendant : les radars, eux, n'ont RIEN à voir. La capacité n'est pas normalisée.
select cmp_ok(
  (select sum(level) from user_stats where user_id = 'ec000000-0000-0000-0000-00000000000c')::int,
  '>',
  (select sum(level) from user_stats where user_id = 'ec000000-0000-0000-0000-00000000000a')::int,
  'radar : 10 quêtes difficiles construisent un bien plus gros radar que 3 faciles'
);

-- Le grief d'origine : « j'ai fait des quêtes et je suis toujours niveau 1 ».
select cmp_ok(
  (select hunter_level from profiles where id = 'ec000000-0000-0000-0000-00000000000a')::int,
  '>', 1,
  'première journée : le Chasseur a monté de niveau (fini le niveau 1 éternel)'
);

-- ────────────────────────────────────────────────────────────────────────────
-- D — §8 : les pénalités ne touchent JAMAIS la piste du Chasseur
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('ec000000-0000-0000-0000-00000000000d', 'puni@eco.dev', '{"timezone":"UTC"}'::jsonb);

insert into habits (user_id, name, stat, difficulty, recurrence, frequency, created_at)
values ('ec000000-0000-0000-0000-00000000000d', 'ratée', 'FOR', 'hard', 'daily', 1,
        now() - interval '30 days');

-- On le place au rang C, avec de l'XP en cours.
update profiles
  set hunter_level = 250, hunter_xp = 400, hunter_xp_total = 50000, rank = 'C'
  where id = 'ec000000-0000-0000-0000-00000000000d';

-- Journée entièrement ratée → pénalités.
select close_day('ec000000-0000-0000-0000-00000000000d', current_date);

select is(
  (select hunter_xp from profiles where id = 'ec000000-0000-0000-0000-00000000000d'),
  400, '§8 : une journée ratée ne retire pas un seul XP de Chasseur'
);
select is(
  (select hunter_level from profiles where id = 'ec000000-0000-0000-0000-00000000000d'),
  250, '§8 : le niveau du Chasseur ne redescend jamais'
);
select is(
  (select rank from profiles where id = 'ec000000-0000-0000-0000-00000000000d'),
  'C'::hunter_rank, '§8 : le rang ne redescend jamais'
);
-- La sanction existe bien — mais elle frappe le RADAR, pas l'identité.
select cmp_ok(
  (select current_xp from user_stats
   where user_id = 'ec000000-0000-0000-0000-00000000000d' and stat = 'FOR')::int,
  '=', 0,
  'la pénalité mord bien : elle vide l''XP de la stat (plancher 0), pas le rang'
);

-- ────────────────────────────────────────────────────────────────────────────
-- E — Journée neutre : aucun engagement, donc aucun XP de Chasseur
-- ────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data)
values ('ec000000-0000-0000-0000-00000000000e', 'vide@eco.dev', '{"timezone":"UTC"}'::jsonb);

select is(
  daily_pool('ec000000-0000-0000-0000-00000000000e', current_date),
  0::numeric,
  'journée neutre : aucun dû quotidien, donc aucun dénominateur'
);
select is(
  (grant_hunter_xp('ec000000-0000-0000-0000-00000000000e', 100, current_date) ->> 'gain')::int,
  0, 'journée neutre : rien à prouver, rien à gagner (pas de division par zéro)'
);

select * from finish();
rollback;
