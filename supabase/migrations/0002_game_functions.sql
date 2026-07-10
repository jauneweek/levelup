-- ============================================================================
-- LEVELUP — Migration 0002 : durcissement anti-triche + moteur XP/niveaux (M1)
-- Réf : SPEC §3.2 (XP), §3.3 (niveaux/rangs), §3.4 (streaks), §8 (idempotence)
-- CLAUDE.md : « toute la logique de jeu est côté serveur (...) zéro triche »
--
-- Contenu :
--   1. Durcissement RLS : user_stats / habit_logs / streaks passent en lecture
--      seule pour le client (M0 les avait laissés en écriture directe — trou
--      de triche corrigé ici). profiles : rank/global_level/emblem_damage
--      verrouillés, username/timezone restent éditables par le user.
--   2. xp_to_next_level(level) : formule verrouillée 100 × N^1.5 (arrondi).
--   3. rank_for_level(level) : table de rang verrouillée (SPEC §3.3).
--   4. complete_habit(habit_id) : fonction SECURITY DEFINER, idempotente,
--      calcule XP, streak par habitude, level-up, niveau global, rang.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DURCISSEMENT RLS — tables de score en lecture seule pour le client
-- ----------------------------------------------------------------------------
drop policy user_stats_owner on user_stats;
create policy user_stats_read on user_stats
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on user_stats from authenticated;

drop policy habit_logs_owner on habit_logs;
create policy habit_logs_read on habit_logs
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on habit_logs from authenticated;

drop policy streaks_owner on streaks;
create policy streaks_read on streaks
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on streaks from authenticated;

-- profiles : le user garde la main sur username/timezone, pas sur le score.
revoke update on profiles from authenticated;
grant update (username, timezone) on profiles to authenticated;

-- ----------------------------------------------------------------------------
-- 2. FORMULE DE NIVEAU (SPEC §3.3, verrouillée)
-- ----------------------------------------------------------------------------
create function public.xp_to_next_level(p_level int)
returns int
language sql
immutable
as $$
  select round(100 * power(p_level, 1.5))::int;
$$;

-- ----------------------------------------------------------------------------
-- 3. TABLE DE RANG (SPEC §3.3, verrouillée)
-- ----------------------------------------------------------------------------
create function public.rank_for_level(p_level int)
returns hunter_rank
language sql
immutable
as $$
  select case
    when p_level >= 50 then 'S'
    when p_level >= 35 then 'A'
    when p_level >= 20 then 'B'
    when p_level >= 10 then 'C'
    when p_level >= 5  then 'D'
    else 'E'
  end::hunter_rank;
$$;

-- ----------------------------------------------------------------------------
-- 4. complete_habit — cœur de la boucle de jeu (M1)
--
-- Règles appliquées ici (voir SPEC §3.2/§3.3/§3.4) :
--   - XP par difficulté : easy=10, medium=25, hard=50.
--   - Complétée le jour même (avant minuit, TZ user) = XP complet. Le
--     deadline_time ne pilote que les notifications (M3), pas l'XP.
--   - Multiplicateur M1 : streak habitude ≥ 21 jours → ×1.2 permanent.
--     (journée parfaite ×1.5 = M2, potion ×2 = M4, cap ×3 pas atteignable ici)
--   - Idempotence : unique(habit_id, date) — un 2e appel le même jour
--     renvoie already_completed=true sans retoucher l'XP.
--   - Niveau global = floor(moyenne des 5 niveaux de stats).
--   - Rang recalculé après chaque complétion (monotone : les niveaux ne
--     descendent jamais, cf. plancher psychologique SPEC §8).
-- ----------------------------------------------------------------------------
create function public.complete_habit(p_habit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_habit        habits%rowtype;
  v_tz           text;
  v_today        date;
  v_yesterday    date;
  v_base_xp      int;
  v_multiplier   numeric(4, 2) := 1.0;
  v_xp_earned    int;
  v_streak       streaks%rowtype;
  v_new_current  int;
  v_new_best     int;
  v_stat_level   int;
  v_stat_xp      int;
  v_threshold    int;
  v_new_global   int;
  v_new_rank     hunter_rank;
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

  -- Idempotence : déjà complétée aujourd'hui ?
  if exists (
    select 1 from habit_logs where habit_id = p_habit_id and date = v_today
  ) then
    return jsonb_build_object('already_completed', true, 'date', v_today);
  end if;

  v_base_xp := case v_habit.difficulty
    when 'easy' then 10
    when 'medium' then 25
    when 'hard' then 50
  end;

  -- Streak par habitude (créée paresseusement si absente).
  select * into v_streak from streaks
    where user_id = v_user_id and habit_id = p_habit_id;
  if not found then
    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (v_user_id, p_habit_id, 0, 0, null)
    returning * into v_streak;
  end if;

  if v_streak.last_completed_date = v_yesterday then
    v_new_current := v_streak.current + 1;
  else
    v_new_current := 1;
  end if;
  v_new_best := greatest(v_streak.best, v_new_current);

  if v_new_current >= 21 then
    v_multiplier := 1.2;
  end if;

  v_xp_earned := round(v_base_xp * v_multiplier);

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, v_multiplier, false);

  -- Application de l'XP + boucle de level-up sur la stat de l'habitude.
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

  -- Niveau global + rang, recalculés sur les 5 stats.
  select floor(avg(level))::int into v_new_global
    from user_stats where user_id = v_user_id;
  v_new_rank := public.rank_for_level(v_new_global);

  update profiles
    set global_level = v_new_global, rank = v_new_rank
    where id = v_user_id;

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'stat', v_habit.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'global_level', v_new_global,
    'rank', v_new_rank,
    'streak_current', v_new_current,
    'streak_best', v_new_best
  );
end;
$$;

grant execute on function public.complete_habit(uuid) to authenticated;
grant execute on function public.xp_to_next_level(int) to authenticated;
grant execute on function public.rank_for_level(int) to authenticated;
