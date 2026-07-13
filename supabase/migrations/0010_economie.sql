-- ============================================================================
-- ÉCONOMIE — XP, Niveau du Chasseur, Rangs
--
-- Deux pistes de progression, et c'est tout le propos :
--
--  • LE RADAR (les 5 stats) mesure ta CAPACITÉ. XP absolue : 100 / 250 / 500.
--    Dix quêtes difficiles par jour font un grand radar, trois faciles un petit.
--    C'est ta vraie vie, elle n'a pas à être normalisée. Ne se réinitialise jamais.
--
--  • LE CHASSEUR (niveau + rang) mesure ta DISCIPLINE. Il monte à la même vitesse
--    pour tout le monde :
--
--        XP du Chasseur = 1000 × (XP de base de la quête ÷ dû quotidien total)
--
--    Une journée pleine vaut 1000 points, que tu aies 3 quêtes ou 10. Sans cette
--    normalisation, celui qui fait 10 quêtes atteindrait le rang max en 3 mois et
--    celui qui en fait 3 en mettrait 20 : le rang ne voudrait plus rien dire.
--
-- Rythme : 100 niveaux par rang, E → D → C → B → A → S, puis Monarque.
-- Coût d'un niveau : 100 + 1,3 × (niveau − 1). Le premier coûte 100 — soit un
-- dixième d'une journée : on monte de niveau dès sa première quête. Le dernier
-- avant Monarque en coûte 877. Total : ~293 000 XP ≈ 9,5 mois de constance.
--
-- ⚠️ Les pénalités ne touchent JAMAIS l'XP du Chasseur (SPEC §8 : on ne fait
--    jamais redescendre un rang). Une journée ratée ne retire rien — elle ne
--    rapporte simplement rien. Le coût, c'est le temps perdu. Les pénalités
--    continuent de mordre les stats, donc le radar.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. L'XP de base — source unique de vérité
--    Elle était recopiée en dur dans 6 fonctions (`when 'easy' then 10 …`).
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.base_xp(p_difficulty difficulty)
returns int
language sql
immutable
as $$
  select case p_difficulty
    when 'easy'   then 100
    when 'medium' then 250
    when 'hard'   then 500
  end;
$$;

-- Durée d'une période, en jours — sert à ramener un quota à son poids quotidien.
create or replace function public.period_days(p_recurrence recurrence_type)
returns numeric
language sql
immutable
as $$
  select case p_recurrence
    when 'daily'   then 1
    when 'weekly'  then 7
    when 'monthly' then 30
    when 'yearly'  then 365
    else null                     -- 'once' : ce n'est pas un rythme
  end::numeric;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Le DÛ QUOTIDIEN, en XP de base — le dénominateur du Chasseur
--
--    Tout est ramené au jour : « 3 séances par semaine » pèse 3/7 de séance par
--    jour. Une quête `once` en est exclue (elle n'a pas de rythme) — la valider
--    est donc un bonus net, ce qui est exactement ce qu'un jalon doit faire.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.daily_pool(p_user_id uuid, p_date date)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((
      select sum(
        public.base_xp(h.difficulty) * h.frequency / public.period_days(h.recurrence)
      )
      from habits h
      where h.user_id = p_user_id
        and h.active
        and h.created_at::date <= p_date
        and h.recurrence <> 'once'
    ), 0)
    + coalesce((
      select sum(public.base_xp(t.difficulty))
      from todos t
      where t.user_id = p_user_id and t.date = p_date
    ), 0);
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. La courbe du Chasseur
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.hunter_xp_to_next(p_level int)
returns int
language sql
immutable
as $$
  -- 100 au niveau 1 (une quête suffit), 877 juste avant Monarque.
  select (100 + round(1.3 * (greatest(1, p_level) - 1)))::int;
$$;

create or replace function public.rank_for_hunter_level(p_level int)
returns hunter_rank
language sql
immutable
set search_path = public
as $$
  select case
    when p_level > 600 then 'M'   -- Monarque : plus rien au-dessus
    when p_level > 500 then 'S'
    when p_level > 400 then 'A'
    when p_level > 300 then 'B'
    when p_level > 200 then 'C'
    when p_level > 100 then 'D'
    else 'E'
  end::hunter_rank;
$$;

-- Le niveau AFFICHÉ : 1 à 100 à l'intérieur du rang. Au 100e, on change de rang
-- et le compteur repart à 1 — c'est une promotion, jamais une perte.
create or replace function public.hunter_level_in_rank(p_level int)
returns int
language sql
immutable
as $$
  select case
    when p_level > 600 then p_level - 600   -- Monarque : le compteur continue
    else ((p_level - 1) % 100) + 1
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Le compteur du Chasseur, sur le profil
-- ─────────────────────────────────────────────────────────────────────────────

alter table profiles
  add column hunter_level    int    not null default 1,
  add column hunter_xp       int    not null default 0,   -- XP dans le niveau courant
  add column hunter_xp_total bigint not null default 0;   -- cumul de carrière, monotone

alter table profiles
  add constraint profiles_hunter_level_positive check (hunter_level >= 1),
  add constraint profiles_hunter_xp_positive    check (hunter_xp >= 0);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Attribution de l'XP du Chasseur
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.grant_hunter_xp(
  p_user_id  uuid,
  p_base_xp  numeric,   -- XP de BASE de la quête (avant multiplicateurs)
  p_date     date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pool      numeric;
  v_gain      int;
  v_level     int;
  v_xp        int;
  v_threshold int;
  v_old_level int;
  v_old_rank  hunter_rank;
  v_new_rank  hunter_rank;
begin
  v_pool := public.daily_pool(p_user_id, p_date);

  -- Journée neutre : aucun engagement, donc rien à prouver et rien à gagner.
  if v_pool <= 0 then
    return jsonb_build_object('gain', 0, 'leveled_up', false, 'ranked_up', false);
  end if;

  -- ⚠️ On part de l'XP de BASE, pas de l'XP gagnée. Les multiplicateurs (journée
  -- parfaite, série, quête secrète, Ombres) gonflent la CAPACITÉ — donc le radar.
  -- Le rang, lui, doit rester une horloge : une journée pleine vaut 1000, point.
  -- C'est ce qui rend la promesse « Monarque en 9,5 mois » tenable et lisible.
  v_gain := greatest(1, round(1000.0 * p_base_xp / v_pool)::int);

  select hunter_level, hunter_xp, rank
    into v_old_level, v_xp, v_old_rank
    from profiles where id = p_user_id
    for update;

  v_level := v_old_level;
  v_xp := v_xp + v_gain;

  loop
    v_threshold := public.hunter_xp_to_next(v_level);
    exit when v_xp < v_threshold;
    v_xp := v_xp - v_threshold;
    v_level := v_level + 1;
  end loop;

  v_new_rank := public.rank_for_hunter_level(v_level);

  update profiles
    set hunter_level    = v_level,
        hunter_xp       = v_xp,
        hunter_xp_total = hunter_xp_total + v_gain,
        rank            = v_new_rank
    where id = p_user_id;

  return jsonb_build_object(
    'gain',          v_gain,
    'level',         v_level,
    'level_in_rank', public.hunter_level_in_rank(v_level),
    'xp',            v_xp,
    'to_next',       public.hunter_xp_to_next(v_level),
    'rank',          v_new_rank,
    'leveled_up',    v_level > v_old_level,
    'ranked_up',     v_new_rank <> v_old_rank
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Le rang ne se déduit plus de la moyenne des stats
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.recompute_profile_progress(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_global int;
begin
  -- `global_level` reste la moyenne des 5 stats : c'est le résumé du RADAR (la
  -- capacité). Il alimente encore le Fantôme (comparaison J-30) et le Journal.
  select floor(avg(level))::int into v_new_global
    from user_stats where user_id = p_user_id;

  -- Mais le RANG n'en dérive plus : il vient de la piste du Chasseur. Sinon un
  -- gros volume de quêtes achèterait un rang, alors que le rang doit se gagner
  -- à la régularité.
  update profiles
    set global_level = v_new_global,
        rank = public.rank_for_hunter_level(hunter_level)
    where id = p_user_id;
end;
$$;

revoke execute on function public.base_xp(difficulty)              from public, anon, authenticated;
revoke execute on function public.period_days(recurrence_type)     from public, anon, authenticated;
revoke execute on function public.daily_pool(uuid, date)           from public, anon, authenticated;
revoke execute on function public.grant_hunter_xp(uuid, numeric, date) from public, anon, authenticated;
revoke execute on function public.rank_for_hunter_level(int)       from public, anon, authenticated;
revoke execute on function public.hunter_level_in_rank(int)        from public, anon, authenticated;
-- `hunter_xp_to_next` sert aussi à l'affichage de la barre côté client.
grant execute on function public.hunter_xp_to_next(int) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Les fonctions de jeu passent par base_xp() au lieu de recopier l'échelle
--    (elles gagnent aussi, pour les trois complete_*, l'XP du Chasseur)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.complete_habit(p_habit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id            uuid := auth.uid();
  v_habit              habits%rowtype;
  v_tz                 text;
  v_today              date;
  v_yesterday          date;
  v_local_time         time;
  v_base_xp            int;
  v_multiplier         numeric(4, 2) := 1.0;
  v_shadow_bonus       numeric(4, 2);
  v_hunter             jsonb;
  v_xp_earned          int;
  v_streak             streaks%rowtype;
  v_new_current        int;
  v_new_best           int;
  v_stat_level         int;
  v_stat_xp            int;
  v_threshold          int;
  v_due                int;
  v_done               int;
  v_potion_active      boolean;
  v_rush_habit_id      uuid;
  v_secret             secret_quests%rowtype;
  v_secret_result      jsonb := null;
  v_item               items;
  v_chest              events_log%rowtype;
  v_today_completed    int;
  v_quest              record;
  v_completions_before int;
  v_fills_day          boolean;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_habit from habits
    where id = p_habit_id and user_id = v_user_id;
  if not found then
    raise exception 'habit not found or not owned by user' using errcode = '42501';
  end if;
  if not v_habit.active then
    raise exception 'habit is not active' using errcode = 'P0001';
  end if;

  select timezone into v_tz from profiles where id = v_user_id;
  v_today := (now() at time zone v_tz)::date;
  v_yesterday := v_today - 1;
  v_local_time := (now() at time zone v_tz)::time;

  -- Le garde n'est plus « déjà fait aujourd'hui » mais « quota de la période
  -- rempli ». Un daily ×3 se valide trois fois ; un weekly ×2 se valide deux
  -- fois dans la semaine, le jour qu'on veut.
  if public.habit_remaining(p_habit_id, v_today) = 0 then
    return jsonb_build_object(
      'already_completed', true,      -- conservé : le client s'en sert déjà
      'quota_filled', true,
      'date', v_today
    );
  end if;

  select coalesce(completions, 0) into v_completions_before
    from habit_logs where habit_id = p_habit_id and date = v_today;
  v_completions_before := coalesce(v_completions_before, 0);

  v_base_xp := public.base_xp(v_habit.difficulty);

  select * into v_streak from streaks
    where user_id = v_user_id and habit_id = p_habit_id;
  if not found then
    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (v_user_id, p_habit_id, 0, 0, null)
    returning * into v_streak;
  end if;

  -- Le streak par habitude n'avance qu'UNE fois par jour — et, pour un quota
  -- journalier, seulement quand le quota du jour est REMPLI. Sans ce garde, un
  -- « daily ×3 » ferait grimper le streak de 3 en une seule journée, et
  -- close_day le remettrait à 0 le soir même pour quota incomplet.
  v_fills_day := case
    when v_habit.recurrence = 'daily' then v_completions_before + 1 >= v_habit.frequency
    else v_completions_before = 0
  end;

  if v_fills_day then
    if v_streak.last_completed_date = v_yesterday then
      v_new_current := v_streak.current + 1;
    else
      v_new_current := 1;
    end if;
  else
    v_new_current := v_streak.current;
  end if;
  v_new_best := greatest(v_streak.best, v_new_current);

  if v_new_current >= 21 then
    v_multiplier := 1.2;
  end if;

  -- Heure de rush (§3.6) : l'habitude tirée au sort vaut x2 avant midi.
  select payload ->> 'habit_id' into v_rush_habit_id
    from events_log
    where user_id = v_user_id and date = v_today and event_type = 'rush';

  if v_rush_habit_id is not null and v_rush_habit_id::uuid = p_habit_id
     and v_local_time < time '12:00' then
    v_multiplier := v_multiplier * 2;
  end if;

  -- Quête secrète (§3.14) : révélée seulement à la complétion.
  select * into v_secret from secret_quests
    where user_id = v_user_id and date = v_today
      and target_type = 'habit' and target_id = p_habit_id and not revealed;

  if found then
    update secret_quests set revealed = true where id = v_secret.id;

    if v_secret.reward ->> 'type' = 'xp_double' then
      v_multiplier := v_multiplier * 2;
      v_secret_result := jsonb_build_object('type', 'xp_double');
    elsif v_secret.reward ->> 'type' = 'item' then
      v_item := public.grant_random_item(v_user_id, coalesce(v_secret.reward ->> 'rarity', 'common'));
      v_secret_result := jsonb_build_object('type', 'item', 'item_name', v_item.name);
    elsif v_secret.reward ->> 'type' = 'shield' then
      update streaks set shields = least(3, shields + 1)
        where user_id = v_user_id and habit_id is null;
      v_secret_result := jsonb_build_object('type', 'shield');
    end if;
  end if;

  select exists (
    select 1 from events_log
    where user_id = v_user_id and date = v_today and event_type = 'potion'
  ) into v_potion_active;

  -- Bonus « dernière quête du jour » (§3.2/§3.8). Il se lit sur le DÛ DU JOUR :
  -- valider une quête hebdomadaire ne boucle pas la journée, donc ne le déclenche
  -- pas. Mesuré AVANT l'écriture du log, donc `done` est bien l'état d'avant.
  select o.due, o.done into v_due, v_done
    from public.day_obligation(v_user_id, v_today) o;

  if v_due > 0
     and v_habit.recurrence = 'daily'
     and v_done = v_due - 1 then
    v_multiplier := v_multiplier * (case when v_potion_active then 3.0 else 1.5 end);
  end if;

  v_multiplier := least(3.0, v_multiplier);

  -- Bonus passif des Ombres (§3.11) : couche séparée, hors du cap x3.
  v_shadow_bonus := public.shadow_xp_bonus_multiplier(v_user_id, v_habit.stat);

  v_xp_earned := round(v_base_xp * v_multiplier * v_shadow_bonus);

  if v_fills_day then
    update streaks
      set current = v_new_current, best = v_new_best, last_completed_date = v_today
      where id = v_streak.id;
  end if;

  -- UNIQUE(habit_id, date) est conservé pour l'idempotence des crons : une
  -- complétation supplémentaire incrémente donc le compteur de la ligne du jour
  -- au lieu d'en créer une seconde.
  insert into habit_logs (habit_id, user_id, date, completions, completed_at,
                          xp_earned, multiplier, is_express, express_count)
  values (p_habit_id, v_user_id, v_today, 1, now(),
          v_xp_earned, v_multiplier, false, 0)
  on conflict (habit_id, date) do update
    set completions  = habit_logs.completions + 1,
        completed_at = now(),
        xp_earned    = habit_logs.xp_earned + excluded.xp_earned,
        multiplier   = excluded.multiplier;

  perform public.check_shadow_extraction(v_user_id, p_habit_id);

  -- Coffre mystère (§3.6) : 3 habitudes complétées aujourd'hui.
  select * into v_chest from events_log
    where user_id = v_user_id and date = v_today and event_type = 'chest' and not resolved;

  if found then
    select count(*) into v_today_completed
      from habit_logs
      where user_id = v_user_id and date = v_today and completed_at is not null;

    if v_today_completed >= 3 then
      update events_log set resolved = true where id = v_chest.id;
      v_item := public.grant_random_item(v_user_id, 'common');
    end if;
  end if;

  -- Progression des quêtes hebdomadaires de la stat concernée. La progression
  -- est bornée à la cible : une quête atteinte se ferme, elle ne continue pas
  -- à monter (sinon la récompense se rejouerait).
  for v_quest in
    select id, progress, target from quests
    where user_id = v_user_id and type = 'weekly' and status = 'active'
      and (definition ->> 'stat') = v_habit.stat::text
  loop
    if v_quest.progress + 1 >= v_quest.target then
      update quests set progress = v_quest.target, status = 'completed'
        where id = v_quest.id;
      perform public.apply_quest_reward(v_user_id, v_quest.id);
    else
      update quests set progress = v_quest.progress + 1 where id = v_quest.id;
    end if;
  end loop;

  select level, current_xp into v_stat_level, v_stat_xp
    from user_stats
    where user_id = v_user_id and stat = v_habit.stat
    for update;

  v_stat_xp := v_stat_xp + v_xp_earned;
  loop
    v_threshold := xp_to_next_level(v_stat_level);
    exit when v_stat_xp < v_threshold;
    v_stat_xp := v_stat_xp - v_threshold;
    v_stat_level := v_stat_level + 1;
  end loop;

  update user_stats
    set level = v_stat_level, current_xp = v_stat_xp
    where user_id = v_user_id and stat = v_habit.stat;

  -- ── XP du Chasseur (piste DISCIPLINE, distincte du radar) ────────────────
  -- On passe l'XP de BASE, pas l'XP gagnee : les multiplicateurs gonflent la
  -- capacite (le radar), jamais le rang. La normalisation par le du quotidien
  -- se fait dans grant_hunter_xp.
  v_hunter := public.grant_hunter_xp(v_user_id, v_base_xp, v_today);

  perform public.recompute_profile_progress(v_user_id);

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'shadow_bonus', v_shadow_bonus,
    'hunter', v_hunter,
    'stat', v_habit.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'streak', v_new_current,
    'secret', v_secret_result,
    'remaining', public.habit_remaining(p_habit_id, v_today),
    'frequency', v_habit.frequency,
    'date', v_today
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.complete_habit_express(p_habit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id            uuid := auth.uid();
  v_habit              habits%rowtype;
  v_tz                 text;
  v_today              date;
  v_yesterday          date;
  v_express_count      int;
  v_base_xp            int;
  v_xp_earned          int;
  v_streak             streaks%rowtype;
  v_new_current        int;
  v_new_best           int;
  v_stat_level         int;
  v_stat_xp            int;
  v_threshold          int;
  v_shadow_bonus       numeric(4, 2);
  v_hunter             jsonb;
  v_completions_before int;
  v_fills_day          boolean;
  v_quest              record;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_habit from habits
    where id = p_habit_id and user_id = v_user_id;
  if not found then
    raise exception 'habit not found or not owned by user' using errcode = '42501';
  end if;
  if not v_habit.active then
    raise exception 'habit is not active' using errcode = 'P0001';
  end if;
  if v_habit.minimal_version is null then
    raise exception 'habit has no minimal version defined' using errcode = 'P0001';
  end if;

  select timezone into v_tz from profiles where id = v_user_id;
  v_today := (now() at time zone v_tz)::date;
  v_yesterday := v_today - 1;

  if public.habit_remaining(p_habit_id, v_today) = 0 then
    return jsonb_build_object('already_completed', true, 'quota_filled', true, 'date', v_today);
  end if;

  -- Cap 2 express/jour. On compte les COMPLÉTIONS express, pas les lignes :
  -- avec un quota journalier > 1, une même habitude peut en consommer deux.
  select coalesce(sum(express_count), 0)::int into v_express_count
    from habit_logs where user_id = v_user_id and date = v_today;

  if v_express_count >= 2 then
    return jsonb_build_object('express_limit_reached', true, 'date', v_today);
  end if;

  select coalesce(completions, 0) into v_completions_before
    from habit_logs where habit_id = p_habit_id and date = v_today;
  v_completions_before := coalesce(v_completions_before, 0);

  v_base_xp := public.base_xp(v_habit.difficulty);

  select * into v_streak from streaks
    where user_id = v_user_id and habit_id = p_habit_id;
  if not found then
    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (v_user_id, p_habit_id, 0, 0, null)
    returning * into v_streak;
  end if;

  v_fills_day := case
    when v_habit.recurrence = 'daily' then v_completions_before + 1 >= v_habit.frequency
    else v_completions_before = 0
  end;

  if v_fills_day then
    if v_streak.last_completed_date = v_yesterday then
      v_new_current := v_streak.current + 1;
    else
      v_new_current := 1;
    end if;
  else
    v_new_current := v_streak.current;
  end if;
  v_new_best := greatest(v_streak.best, v_new_current);

  -- 50% de l'XP (§3.10). Pas de multiplicateur : l'express sauve la mise, il ne
  -- récompense pas. Le bonus passif des Ombres reste dû.
  v_shadow_bonus := public.shadow_xp_bonus_multiplier(v_user_id, v_habit.stat);
  v_xp_earned := round(v_base_xp * 0.5 * v_shadow_bonus);

  if v_fills_day then
    update streaks
      set current = v_new_current, best = v_new_best, last_completed_date = v_today
      where id = v_streak.id;
  end if;

  insert into habit_logs (habit_id, user_id, date, completions, completed_at,
                          xp_earned, multiplier, is_express, express_count)
  values (p_habit_id, v_user_id, v_today, 1, now(),
          v_xp_earned, 0.5, true, 1)
  on conflict (habit_id, date) do update
    set completions   = habit_logs.completions + 1,
        express_count = habit_logs.express_count + 1,
        is_express    = true,
        completed_at  = now(),
        xp_earned     = habit_logs.xp_earned + excluded.xp_earned,
        multiplier    = excluded.multiplier;

  perform public.check_shadow_extraction(v_user_id, p_habit_id);

  select level, current_xp into v_stat_level, v_stat_xp
    from user_stats
    where user_id = v_user_id and stat = v_habit.stat
    for update;

  v_stat_xp := v_stat_xp + v_xp_earned;
  loop
    v_threshold := xp_to_next_level(v_stat_level);
    exit when v_stat_xp < v_threshold;
    v_stat_xp := v_stat_xp - v_threshold;
    v_stat_level := v_stat_level + 1;
  end loop;

  update user_stats
    set level = v_stat_level, current_xp = v_stat_xp
    where user_id = v_user_id and stat = v_habit.stat;

  -- Version minimale : moitie de l'XP, donc moitie de credit sur le rang aussi.
  -- L'express sauve la journee, il ne l'achete pas.
  v_hunter := public.grant_hunter_xp(v_user_id, v_base_xp * 0.5, v_today);

  perform public.recompute_profile_progress(v_user_id);

  -- Une complétion express reste une complétion : elle fait progresser les
  -- quêtes hebdomadaires au même titre qu'une complète (§3.10).
  for v_quest in
    select id, progress, target from quests
    where user_id = v_user_id and type = 'weekly' and status = 'active'
      and (definition ->> 'stat') = v_habit.stat::text
  loop
    if v_quest.progress + 1 >= v_quest.target then
      update quests set progress = v_quest.target, status = 'completed'
        where id = v_quest.id;
      perform public.apply_quest_reward(v_user_id, v_quest.id);
    else
      update quests set progress = v_quest.progress + 1 where id = v_quest.id;
    end if;
  end loop;

  return jsonb_build_object(
    'already_completed', false,
    'is_express', true,
    'hunter', v_hunter,
    'xp_earned', v_xp_earned,
    'stat', v_habit.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'streak', v_new_current,
    'express_left', greatest(0, 2 - (v_express_count + 1)),
    'remaining', public.habit_remaining(p_habit_id, v_today),
    'date', v_today
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.complete_todo(p_todo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id       uuid := auth.uid();
  v_todo          todos%rowtype;
  v_tz            text;
  v_today         date;
  v_base_xp       int;
  v_multiplier    numeric(4, 2) := 1.0;
  v_shadow_bonus  numeric(4, 2);
  v_hunter             jsonb;
  v_xp_earned     int;
  v_stat_level    int;
  v_stat_xp       int;
  v_threshold     int;
  v_due           int;
  v_done          int;
  v_potion_active boolean;
  v_secret        secret_quests%rowtype;
  v_secret_result jsonb := null;
  v_item          items;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_todo from todos
    where id = p_todo_id and user_id = v_user_id;
  if not found then
    raise exception 'todo not found or not owned by user' using errcode = '42501';
  end if;
  if v_todo.completed_at is not null then
    return jsonb_build_object('already_completed', true, 'date', v_todo.date);
  end if;

  select timezone into v_tz from profiles where id = v_user_id;
  v_today := (now() at time zone v_tz)::date;

  -- Une todo se valide le jour où elle est prévue, pas la veille ni le lendemain.
  if v_todo.date <> v_today then
    raise exception 'todo is not schedulable today' using errcode = 'P0001';
  end if;

  v_base_xp := public.base_xp(v_todo.difficulty);

  select * into v_secret from secret_quests
    where user_id = v_user_id and date = v_today
      and target_type = 'todo' and target_id = p_todo_id and not revealed;

  if found then
    update secret_quests set revealed = true where id = v_secret.id;

    if v_secret.reward ->> 'type' = 'xp_double' then
      v_multiplier := v_multiplier * 2;
      v_secret_result := jsonb_build_object('type', 'xp_double');
    elsif v_secret.reward ->> 'type' = 'item' then
      v_item := public.grant_random_item(v_user_id, coalesce(v_secret.reward ->> 'rarity', 'common'));
      v_secret_result := jsonb_build_object('type', 'item', 'item_name', v_item.name);
    elsif v_secret.reward ->> 'type' = 'shield' then
      update streaks set shields = least(3, shields + 1)
        where user_id = v_user_id and habit_id is null;
      v_secret_result := jsonb_build_object('type', 'shield');
    end if;
  end if;

  select exists (
    select 1 from events_log
    where user_id = v_user_id and date = v_today and event_type = 'potion'
  ) into v_potion_active;

  select o.due, o.done into v_due, v_done
    from public.day_obligation(v_user_id, v_today) o;

  if v_todo.date = v_today and v_due > 0 and v_done = v_due - 1 then
    v_multiplier := v_multiplier * (case when v_potion_active then 3.0 else 1.5 end);
  end if;

  v_multiplier := least(3.0, v_multiplier);
  v_shadow_bonus := public.shadow_xp_bonus_multiplier(v_user_id, v_todo.stat);
  v_xp_earned := round(v_base_xp * v_multiplier * v_shadow_bonus);

  update todos
    set completed_at = now(), xp_earned = v_xp_earned
    where id = p_todo_id;

  select level, current_xp into v_stat_level, v_stat_xp
    from user_stats
    where user_id = v_user_id and stat = v_todo.stat
    for update;

  v_stat_xp := v_stat_xp + v_xp_earned;
  loop
    v_threshold := xp_to_next_level(v_stat_level);
    exit when v_stat_xp < v_threshold;
    v_stat_xp := v_stat_xp - v_threshold;
    v_stat_level := v_stat_level + 1;
  end loop;

  update user_stats
    set level = v_stat_level, current_xp = v_stat_xp
    where user_id = v_user_id and stat = v_todo.stat;

  -- XP du Chasseur : une todo compte dans le du quotidien, donc dans le rang.
  v_hunter := public.grant_hunter_xp(v_user_id, v_base_xp, v_today);

  perform public.recompute_profile_progress(v_user_id);

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'hunter', v_hunter,
    'stat', v_todo.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'secret', v_secret_result,
    'date', v_todo.date
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.close_day(p_user_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_profile              profiles%rowtype;
  v_due                  int;
  v_done                 int;
  v_is_neutral_day       boolean;
  v_day_rate             numeric;
  v_is_perfect_day       boolean;
  v_completion_rate_7d   numeric;
  v_is_slump             boolean;
  v_is_abuse_day         boolean;
  v_new_consecutive      int;
  v_penalty_multiplier   numeric(4, 2);
  v_cursed_active        boolean;
  v_habit                record;
  v_todo                 record;
  v_base_xp              int;
  v_penalty              int;
  v_missing              int;
  v_period_start         date;
  v_done_period          int;
  v_closure_id           uuid;
  v_streak_global        streaks%rowtype;
  v_old_streak_current   int;
  v_new_streak_current   int;
  v_new_streak_best      int;
  v_new_shields          int;
  v_new_emblem           int;
  v_new_global           int;
  v_boss                 boss_fights%rowtype;
  v_just_spawned         boolean := false;
  v_boss_active_after    boolean := false;
  v_boss_age_days        int;
  v_highest_stat         stat_type;
  v_penalty_xp           int;
  v_redemption           quests%rowtype;
  v_target_restore       int;
  v_titles               text[] := array['Éveillé','Régulier','Discipline de Fer','Inarrêtable','Monarque'];
  v_thresholds           int[] := array[7,21,42,66,100];
  i                      int;
  v_unlocked             boolean;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text || p_date::text));

  if exists (
    select 1 from daily_snapshots where user_id = p_user_id and date = p_date
  ) then
    return jsonb_build_object('already_processed', true, 'date', p_date);
  end if;

  select * into v_profile from profiles where id = p_user_id;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  -- Le dû du jour : quotas JOURNALIERS + todos. Rien d'autre n'est dû ce soir.
  select o.due, o.done into v_due, v_done
    from public.day_obligation(p_user_id, p_date) o;

  -- ⚠️ Journée NEUTRE (§3.5.3). Aucune obligation aujourd'hui → la journée
  -- n'est ni parfaite ni ratée. Sans ce garde, `done >= due` serait vrai
  -- (0 >= 0) et une journée sans la moindre quête offrirait un streak gratuit.
  v_is_neutral_day := (v_due = 0);
  v_day_rate       := case when v_is_neutral_day then 1.0
                           else v_done::numeric / v_due end;
  v_is_perfect_day := (not v_is_neutral_day) and v_done >= v_due;

  v_completion_rate_7d := public.completion_rate_7d(p_user_id, p_date);

  v_is_slump     := v_completion_rate_7d < 0.40;
  v_is_abuse_day := (not v_is_slump) and (not v_is_neutral_day) and (v_day_rate < 0.50);

  v_new_consecutive := case when v_is_abuse_day then v_profile.consecutive_abuse_days + 1
                            else 0 end;

  v_penalty_multiplier := case
    when v_is_slump then 1.0
    when not v_is_abuse_day then 1.0
    when v_new_consecutive >= 3 then 2.0
    when v_new_consecutive = 2 then 1.5
    else 1.0
  end;

  select exists (
    select 1 from events_log
    where user_id = p_user_id and date = p_date and event_type = 'cursed'
  ) into v_cursed_active;
  if v_cursed_active then
    v_penalty_multiplier := v_penalty_multiplier * 2;
  end if;

  -- ─── Pénalités sur les quotas JOURNALIERS (§3.5.2) ────────────────────────
  -- Le manquant se paie à l'unité : un « daily ×3 » fait 1 fois coûte 2 × 40%.
  for v_habit in
    select h.id, h.stat, h.difficulty, h.frequency,
           coalesce(hl.completions, 0) as done_today
    from habits h
    left join habit_logs hl on hl.habit_id = h.id and hl.date = p_date
    where h.user_id = p_user_id
      and h.active
      and h.recurrence = 'daily'
      and h.created_at::date <= p_date
      and coalesce(hl.completions, 0) < h.frequency
  loop
    v_missing := v_habit.frequency - v_habit.done_today;

    v_base_xp := public.base_xp(v_habit.difficulty);
    v_penalty := round(v_base_xp * 0.4 * v_missing * v_penalty_multiplier);

    update user_stats
      set current_xp = greatest(0, current_xp - v_penalty)
      where user_id = p_user_id and stat = v_habit.stat;

    -- La ligne du jour existe peut-être déjà (quota partiellement rempli) :
    -- on ne peut donc pas insérer sec — on décrémente l'XP de la ligne.
    insert into habit_logs (habit_id, user_id, date, completions, completed_at,
                            xp_earned, multiplier, is_express, express_count)
    values (v_habit.id, p_user_id, p_date, 0, null,
            -v_penalty, v_penalty_multiplier, false, 0)
    on conflict (habit_id, date) do update
      set xp_earned = habit_logs.xp_earned - v_penalty;

    -- Le streak par habitude ne survit qu'à un quota REMPLI.
    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (p_user_id, v_habit.id, 0, 0, null)
    on conflict (user_id, habit_id) where habit_id is not null
    do update set current = 0;
  end loop;

  -- ─── Pénalités sur les todos ratées : même formule, pas de streak ─────────
  for v_todo in
    select id, stat, difficulty from todos
    where user_id = p_user_id and date = p_date and completed_at is null
  loop
    v_base_xp := public.base_xp(v_todo.difficulty);
    v_penalty := round(v_base_xp * 0.4 * v_penalty_multiplier);

    update user_stats
      set current_xp = greatest(0, current_xp - v_penalty)
      where user_id = p_user_id and stat = v_todo.stat;

    update todos set xp_earned = -v_penalty where id = v_todo.id;
  end loop;

  -- ─── Clôture des périodes non journalières (§3.5.2) ───────────────────────
  -- Une quête hebdo/mensuelle/annuelle n'est due aucun jour précis : elle ne
  -- peut être jugée qu'à la FIN de sa période. `period_closures` rend ce
  -- jugement rejouable sans double peine (cron relancé, rattrapage).
  for v_habit in
    select h.id, h.stat, h.difficulty, h.recurrence, h.frequency
    from habits h
    where h.user_id = p_user_id
      and h.active
      and h.recurrence in ('weekly', 'monthly', 'yearly')
      and p_date = public.period_end(h.recurrence, p_date)
      -- On ne reproche pas un quota qu'il était impossible de tenir : une quête
      -- créée en cours de période échappe au jugement de CETTE période.
      and h.created_at::date <= public.period_start(h.recurrence, p_date)
    order by h.created_at, h.id      -- ordre déterministe : testable
  loop
    v_period_start := public.period_start(v_habit.recurrence, p_date);
    v_done_period  := public.habit_period_completions(v_habit.id, p_date);
    v_missing      := greatest(0, v_habit.frequency - v_done_period);

    v_base_xp := public.base_xp(v_habit.difficulty);
    v_penalty := round(v_base_xp * 0.4 * v_missing * v_penalty_multiplier);

    -- ⚠️ Remis à null à CHAQUE tour : `returning ... into` ne touche pas la
    -- variable quand `do nothing` avale la ligne — elle garderait sinon la
    -- valeur du tour précédent, et on pénaliserait une période déjà jugée.
    v_closure_id := null;

    insert into period_closures (
      user_id, habit_id, recurrence, period_start, period_end,
      quota, completed, missing, xp_penalty
    )
    values (
      p_user_id, v_habit.id, v_habit.recurrence, v_period_start, p_date,
      v_habit.frequency, v_done_period, v_missing, v_penalty
    )
    on conflict (habit_id, period_start) do nothing
    returning id into v_closure_id;

    if v_closure_id is null then
      continue;                              -- période déjà jugée
    end if;

    if v_penalty > 0 then
      update user_stats
        set current_xp = greatest(0, current_xp - v_penalty)
        where user_id = p_user_id and stat = v_habit.stat;
    end if;

    -- Streak par période : il ne survit qu'à un quota rempli.
    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (p_user_id, v_habit.id,
            case when v_missing = 0 then 1 else 0 end,
            case when v_missing = 0 then 1 else 0 end,
            case when v_missing = 0 then p_date else null end)
    on conflict (user_id, habit_id) where habit_id is not null
    do update set
      current = case when v_missing = 0 then streaks.current + 1 else 0 end,
      best    = greatest(streaks.best,
                         case when v_missing = 0 then streaks.current + 1 else 0 end),
      last_completed_date = case when v_missing = 0 then p_date
                                 else streaks.last_completed_date end;
  end loop;

  -- ─── Quêtes temporaires : archivées à la fin de leur période (§3.5.1) ─────
  update habits
    set active = false
    where user_id = p_user_id
      and active
      and temporary
      and recurrence <> 'once'
      and p_date = public.period_end(recurrence, p_date);

  -- ─── Streak global + boucliers (§3.4) ─────────────────────────────────────
  select * into v_streak_global from streaks
    where user_id = p_user_id and habit_id is null;
  v_old_streak_current := v_streak_global.current;

  if v_is_neutral_day then
    -- Journée neutre : le streak est GELÉ. Il ne monte pas (on n'a rien fait),
    -- il ne casse pas (on n'avait rien à faire), et aucun bouclier n'est brûlé.
    v_new_streak_current := v_streak_global.current;
    v_new_streak_best    := v_streak_global.best;
    v_new_shields        := v_streak_global.shields;

  elsif v_is_perfect_day then
    v_new_streak_current := v_streak_global.current + 1;
    v_new_streak_best := greatest(v_streak_global.best, v_new_streak_current);
    v_new_shields := case when v_new_streak_current % 10 = 0
                          then least(3, v_streak_global.shields + 1)
                          else v_streak_global.shields end;

  elsif v_streak_global.shields > 0 then
    v_new_streak_current := v_streak_global.current;
    v_new_streak_best := v_streak_global.best;
    v_new_shields := v_streak_global.shields - 1;

    perform public.enqueue_notification(
      p_user_id, 'streak_shield',
      jsonb_build_object('streak', v_new_streak_current, 'shields', v_new_shields)
    );
  else
    v_new_streak_current := 0;
    v_new_streak_best := v_streak_global.best;
    v_new_shields := v_streak_global.shields;
  end if;

  update streaks
    set current = v_new_streak_current,
        best = v_new_streak_best,
        shields = v_new_shields,
        last_completed_date = p_date
    where id = v_streak_global.id;

  -- Quête de rédemption (§3.5.4).
  if (not v_is_neutral_day) and (not v_is_perfect_day)
     and v_streak_global.shields = 0
     and v_old_streak_current > 0 and v_new_streak_current = 0 then
    insert into quests (user_id, type, definition, progress, target, reward, status)
    values (
      p_user_id, 'redemption',
      jsonb_build_object('old_streak', v_old_streak_current),
      0, 3,
      jsonb_build_object('type', 'streak_restore', 'percent', 50),
      'active'
    );
    perform public.enqueue_notification(
      p_user_id, 'redemption', jsonb_build_object('streak', v_old_streak_current)
    );
  end if;

  select * into v_redemption from quests
    where user_id = p_user_id and type = 'redemption' and status = 'active'
    order by created_at desc limit 1;

  if found then
    if v_is_perfect_day then
      if v_redemption.progress + 1 >= v_redemption.target then
        v_target_restore := ceil((v_redemption.definition ->> 'old_streak')::numeric * 0.5)::int;
        if v_new_streak_current < v_target_restore then
          update streaks
            set current = v_target_restore,
                best = greatest(best, v_target_restore)
            where id = v_streak_global.id;
          v_new_streak_current := v_target_restore;
        end if;
        update quests set progress = v_redemption.target, status = 'completed'
          where id = v_redemption.id;
      else
        update quests set progress = v_redemption.progress + 1 where id = v_redemption.id;
      end if;
    elsif not v_is_neutral_day then
      -- Une journée neutre ne casse pas la rédemption : on n'a rien raté.
      update quests set progress = 0 where id = v_redemption.id;
    end if;
  end if;

  -- Titres de streak (§3.4).
  for i in 1..array_length(v_thresholds, 1) loop
    if v_new_streak_current >= v_thresholds[i] then
      v_unlocked := public.unlock_title_if_new(p_user_id, v_titles[i]);
      if v_unlocked then
        update user_titles set unlocked_at = p_date::timestamptz
          where user_id = p_user_id
            and title_id = (select id from titles where name = v_titles[i]);
        perform public.enqueue_notification(
          p_user_id, 'streak_milestone',
          jsonb_build_object('streak', v_new_streak_current, 'title_next', v_titles[i])
        );
      end if;
    end if;
  end loop;

  -- Boss de la Procrastination (§3.7). Une journée neutre ne le blesse ni ne
  -- le soigne : les deux branches ci-dessous l'excluent d'elles-mêmes.
  select * into v_boss from boss_fights
    where user_id = p_user_id and status = 'active'
    limit 1;

  if not found and v_new_consecutive >= 3 then
    insert into boss_fights (user_id, hp, max_hp, spawned_on)
    values (p_user_id, 3, 3, p_date)
    returning * into v_boss;

    v_just_spawned := true;
    perform public.enqueue_notification(
      p_user_id, 'boss_spawn', jsonb_build_object('boss_hp', v_boss.hp)
    );
  end if;

  if v_boss.id is not null and v_boss.status = 'active' and not v_just_spawned then
    if v_is_perfect_day then
      update boss_fights set hp = hp - 1 where id = v_boss.id
        returning * into v_boss;

      if v_boss.hp <= 0 then
        update boss_fights set hp = 0, status = 'defeated' where id = v_boss.id;
        v_boss.status := 'defeated';

        declare
          v_stat  stat_type;
          v_share int := 30;
          v_lvl   int;
          v_xp    int;
          v_thr   int;
        begin
          for v_stat in select unnest(enum_range(null::stat_type)) loop
            select level, current_xp into v_lvl, v_xp
              from user_stats where user_id = p_user_id and stat = v_stat
              for update;
            v_xp := v_xp + v_share;
            loop
              v_thr := xp_to_next_level(v_lvl);
              exit when v_xp < v_thr;
              v_xp := v_xp - v_thr;
              v_lvl := v_lvl + 1;
            end loop;
            update user_stats set level = v_lvl, current_xp = v_xp
              where user_id = p_user_id and stat = v_stat;
          end loop;
        end;

        perform public.unlock_title_if_new(p_user_id, 'Tueur de Boss');
        update user_titles set unlocked_at = p_date::timestamptz
          where user_id = p_user_id
            and title_id = (select id from titles where name = 'Tueur de Boss');
        perform public.grant_random_item(p_user_id, 'rare');
        perform public.recompute_profile_progress(p_user_id);

        perform public.enqueue_notification(
          p_user_id, 'boss_defeat',
          jsonb_build_object('rank', (select rank from profiles where id = p_user_id))
        );
      else
        perform public.enqueue_notification(
          p_user_id, 'boss_damage', jsonb_build_object('boss_hp', v_boss.hp)
        );
      end if;
    elsif v_is_abuse_day then
      update boss_fights
        set hp = least(max_hp, hp + 1)
        where id = v_boss.id
        returning * into v_boss;

      perform public.enqueue_notification(
        p_user_id, 'boss_heal', jsonb_build_object('boss_hp', v_boss.hp)
      );
    end if;
  end if;

  if v_boss.id is not null and v_boss.status = 'active' then
    v_boss_age_days := p_date - v_boss.spawned_on;

    if v_boss_age_days >= 14 then
      update boss_fights set status = 'timeout' where id = v_boss.id;
      v_boss.status := 'timeout';

      select stat into v_highest_stat from user_stats
        where user_id = p_user_id order by level desc, current_xp desc limit 1;

      select round(current_xp * 0.10)::int into v_penalty_xp
        from user_stats where user_id = p_user_id and stat = v_highest_stat;

      update user_stats
        set current_xp = greatest(0, current_xp - v_penalty_xp)
        where user_id = p_user_id and stat = v_highest_stat;

    elsif v_boss_age_days = 11 and not v_boss.deadline_notified then
      update boss_fights set deadline_notified = true where id = v_boss.id;

      select stat into v_highest_stat from user_stats
        where user_id = p_user_id order by level desc, current_xp desc limit 1;

      perform public.enqueue_notification(
        p_user_id, 'boss_deadline', jsonb_build_object('stat', v_highest_stat)
      );
    end if;
  end if;

  v_boss_active_after := v_boss.id is not null and v_boss.status = 'active';

  -- Le blason ne se répare ni ne se fissure une journée neutre.
  v_new_emblem := case
    when v_boss_active_after then 3
    when v_is_abuse_day then least(2, v_profile.emblem_damage + 1)
    when v_is_perfect_day then greatest(0, v_profile.emblem_damage - 1)
    else v_profile.emblem_damage
  end;

  update profiles
    set consecutive_abuse_days = v_new_consecutive,
        emblem_damage = v_new_emblem
    where id = p_user_id;

  perform public.recompute_profile_progress(p_user_id);
  select global_level into v_new_global from profiles where id = p_user_id;

  insert into daily_snapshots (user_id, date, global_level, stats, streak, completion_rate_7d)
  values (
    p_user_id, p_date, v_new_global,
    (select jsonb_object_agg(stat, jsonb_build_object('level', level, 'current_xp', current_xp))
       from user_stats where user_id = p_user_id),
    v_new_streak_current, v_completion_rate_7d
  );

  return jsonb_build_object(
    'already_processed', false,
    'date', p_date,
    'scheduled_count', v_due,          -- = le dû du jour (quotas journaliers + todos)
    'completed_count', v_done,
    'day_rate', v_day_rate,
    'is_neutral_day', v_is_neutral_day,
    'is_perfect_day', v_is_perfect_day,
    'completion_rate_7d', v_completion_rate_7d,
    'is_slump', v_is_slump,
    'is_abuse_day', v_is_abuse_day,
    'consecutive_abuse_days', v_new_consecutive,
    'penalty_multiplier', v_penalty_multiplier,
    'streak_current', v_new_streak_current,
    'shields', v_new_shields,
    'emblem_damage', v_new_emblem,
    'global_level', v_new_global,
    'boss_active', v_boss_active_after,
    'boss_hp', case when v_boss.id is not null then v_boss.hp else null end,
    'boss_status', v_boss.status
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.draw_daily_event(p_user_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_roll  numeric := random();
  v_type  text;
  v_habit habits%rowtype;
begin
  if exists (
    select 1 from events_log where user_id = p_user_id and date = p_date
  ) then
    return;
  end if;

  if v_roll < 0.12 then
    v_type := 'potion';
  elsif v_roll < 0.20 then
    v_type := 'chest';
  elsif v_roll < 0.30 then
    -- « Encore faisable » remplace « programmée aujourd'hui » : une quête
    -- hebdomadaire dont le quota n'est pas rempli est un candidat légitime.
    select * into v_habit from habits h
      where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
        and public.habit_remaining(h.id, p_date) > 0
      order by random() limit 1;

    v_type := case when v_habit.id is null then 'none' else 'rush' end;
  elsif v_roll < 0.35 then
    v_type := 'cursed';
  else
    v_type := 'none';
  end if;

  insert into events_log (user_id, event_type, date, payload)
  values (
    p_user_id, v_type, p_date,
    case when v_type = 'rush'
         then jsonb_build_object('habit_id', v_habit.id, 'habit_name', v_habit.name)
         else '{}'::jsonb
    end
  );

  if v_type = 'potion' then
    perform public.enqueue_notification(p_user_id, 'event_potion', '{}'::jsonb);
  elsif v_type = 'chest' then
    perform public.enqueue_notification(p_user_id, 'event_chest', '{}'::jsonb);
  elsif v_type = 'rush' then
    perform public.enqueue_notification(
      p_user_id, 'event_rush',
      jsonb_build_object('habit', v_habit.name, 'xp',
        public.base_xp(v_habit.difficulty))
    );
  elsif v_type = 'cursed' then
    perform public.enqueue_notification(
      p_user_id, 'event_cursed',
      jsonb_build_object('rank', (select rank from profiles where id = p_user_id))
    );
  end if;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.get_due_notifications()
 RETURNS TABLE(user_id uuid, habit_id uuid, template_id uuid, trigger_type text, body text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row              record;
  v_local_now        timestamp;
  v_local_today      date;
  v_deadline         timestamp;
  v_minutes_left     numeric;
  v_trigger          text;
  v_ctx              jsonb;
  v_ignored_t30_here boolean;
  v_persona_filter   text[];
  v_tone_filter      text[];
  v_exclude          uuid[];
  v_template         record;
  v_base_xp          int;
  v_habit_streak     int;
  v_vars             jsonb;
begin
  -- Seuls les quotas JOURNALIERS sont rappelés. Une quête hebdomadaire n'est en
  -- retard aucun mardi : lui envoyer un T-30 n'aurait aucun sens. (Un rappel de
  -- fin de période — « il te reste 2 séances avant dimanche » — demanderait de
  -- nouveaux templates : hors périmètre M8, et le seed ne s'invente pas.)
  for v_row in
    select h.id as habit_id, h.user_id, h.name, h.stat, h.difficulty,
           h.deadline_time, p.timezone
    from habits h
    join profiles p on p.id = h.user_id
    where h.active
      and h.deadline_time is not null
      and h.recurrence = 'daily'
  loop
    v_local_now := now() at time zone v_row.timezone;
    v_local_today := v_local_now::date;

    if not exists (
      select 1 from habits h2
      where h2.id = v_row.habit_id and h2.created_at::date <= v_local_today
    ) then
      continue;
    end if;

    -- Quota du jour rempli ? Plus rien à rappeler.
    if public.habit_remaining(v_row.habit_id, v_local_today) = 0 then
      continue;
    end if;

    v_deadline := v_local_today + v_row.deadline_time;
    v_minutes_left := extract(epoch from (v_deadline - v_local_now)) / 60.0;

    if v_minutes_left between 26 and 30 then
      v_trigger := 't30';
    elsif v_minutes_left between 11 and 15 then
      v_trigger := 't15';
    else
      continue;
    end if;

    if exists (
      select 1 from notification_log nl
      join notification_templates nt on nt.id = nl.template_id
      where nl.habit_id = v_row.habit_id
        and nl.sent_at::date = v_local_today
        and nt.trigger_type = v_trigger
    ) then
      continue;
    end if;

    v_ctx := public.get_notification_context(v_row.user_id);

    if (v_ctx ->> 'is_regular')::boolean and v_trigger = 't30' then
      continue;
    end if;

    v_ignored_t30_here := exists (
      select 1 from notification_log nl
      join notification_templates nt on nt.id = nl.template_id
      where nl.habit_id = v_row.habit_id
        and nl.sent_at::date = v_local_today
        and nt.trigger_type = 't30'
    );

    if (v_ctx ->> 'is_slump')::boolean then
      v_persona_filter := null;
      v_tone_filter := array['supportive'];
    elsif v_trigger = 't15' and (v_ctx ->> 'ignored_count_today')::int >= 2 then
      v_persona_filter := array['boss'];
      v_tone_filter := null;
    elsif v_trigger = 't15' and v_ignored_t30_here then
      v_persona_filter := array['system'];
      v_tone_filter := null;
    else
      v_persona_filter := null;
      v_tone_filter := null;
    end if;

    select array_agg(t.tid) into v_exclude
      from (
        select nl.template_id as tid from notification_log nl
        where nl.user_id = v_row.user_id and nl.template_id is not null
        order by nl.sent_at desc limit 5
      ) t;

    select nt.id, nt.template into v_template
      from notification_templates nt
      where nt.active
        and nt.trigger_type = v_trigger
        and (v_persona_filter is null or nt.persona = any(v_persona_filter))
        and (v_tone_filter is null or nt.tone = any(v_tone_filter))
        and (v_exclude is null or nt.id <> all(v_exclude))
      order by -ln(random()) / nt.weight asc
      limit 1;

    if not found then
      continue;
    end if;

    v_base_xp := public.base_xp(v_row.difficulty);

    select s.current into v_habit_streak from streaks s
      where s.user_id = v_row.user_id and s.habit_id = v_row.habit_id;

    v_vars := jsonb_build_object(
      'habit', v_row.name,
      'xp', v_base_xp,
      'penalty', round(v_base_xp * 0.4),
      'minutes_left', round(v_minutes_left),
      'streak', coalesce(v_habit_streak, 0),
      'stat', v_row.stat
    );

    user_id := v_row.user_id;
    habit_id := v_row.habit_id;
    template_id := v_template.id;
    trigger_type := v_trigger;
    body := public.interpolate_template(v_template.template, v_vars);
    return next;
  end loop;
end;
$function$

;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Reprise de l'existant
-- ─────────────────────────────────────────────────────────────────────────────

-- L'échelle d'XP est multipliée par 10 (10/25/50 → 100/250/500). L'XP déjà
-- gagnée la suit : sans ça, tout l'historique deviendrait dérisoire face aux
-- nouvelles quêtes, et le radar d'un joueur de longue date paraîtrait vide.
update user_stats set current_xp = current_xp * 10;
update habit_logs  set xp_earned = xp_earned * 10;
update todos       set xp_earned = xp_earned * 10 where xp_earned is not null;

-- Le ×10 peut faire franchir des seuils : on rejoue la montée de niveau.
do $$
declare
  r       record;
  v_level int;
  v_xp    int;
  v_thr   int;
begin
  for r in select user_id, stat, level, current_xp from user_stats loop
    v_level := r.level;
    v_xp    := r.current_xp;
    loop
      v_thr := public.xp_to_next_level(v_level);
      exit when v_xp < v_thr;
      v_xp    := v_xp - v_thr;
      v_level := v_level + 1;
    end loop;
    update user_stats
      set level = v_level, current_xp = v_xp
      where user_id = r.user_id and stat = r.stat;
  end loop;
end $$;

-- La piste du Chasseur est neuve : tout le monde démarre au niveau 1.
--
-- ⚠️ SAUF que le SPEC §8 interdit de faire redescendre un rang. Un compte qui
-- avait déjà atteint D ou plus (via l'ancienne moyenne des stats) serait
-- rétrogradé à E. On le place donc au PREMIER NIVEAU DE SON RANG ACTUEL plutôt
-- que de lui reprendre ce qu'il a gagné. Un rang ne se perd jamais.
update profiles
set hunter_level = case rank
      when 'D' then 101
      when 'C' then 201
      when 'B' then 301
      when 'A' then 401
      when 'S' then 501
      else 1              -- E (et le cas neuf)
    end,
    hunter_xp = 0,
    hunter_xp_total = 0;

-- Recale global_level (moyenne des stats après le ×10) et le rang (désormais
-- dérivé de la piste du Chasseur).
do $$
declare r record;
begin
  for r in select id from profiles loop
    perform public.recompute_profile_progress(r.id);
  end loop;
end $$;
