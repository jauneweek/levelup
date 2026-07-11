-- ============================================================================
-- LEVELUP — Migration 0003 : le Tribunal de minuit (M2)
-- Réf : SPEC §3.2 (XP), §3.4 (streaks/boucliers), §3.9 (pénalités), §3.16
-- (malus visible), §5 (recompute_levels, check_streaks, cron midnight-close),
-- §8 (idempotence, fuseaux horaires).
--
-- Contenu :
--   1. profiles.consecutive_abuse_days — compteur d'escalade (§3.9).
--   2. recompute_profile_progress(user_id) — recalcul niveau global + rang,
--      extrait de complete_habit() pour être partagé avec close_day().
--   3. complete_habit() — CREATE OR REPLACE : ajout du bonus journée
--      parfaite ×1.5 sur la dernière habitude complétée (roadmap M2),
--      cumulé avec le ×1.2 streak (M1), cap ×3.
--   4. close_day(user_id, date) — cœur du Tribunal de minuit : pénalités
--      (-40%, progressives ×1.5/×2, jamais en slump), streaks (habitude +
--      globale), boucliers (consommation = streak global figé, décision
--      actée avec l'utilisateur), malus visible, snapshot quotidien.
--      Idempotent (verrou advisory + garde sur daily_snapshots).
--   5. run_midnight_close() + pg_cron toutes les 15 min : scanne les users
--      dont l'heure locale vient de passer minuit.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Compteur d'escalade des jours d'abus consécutifs (§3.9)
-- ----------------------------------------------------------------------------
alter table profiles
  add column consecutive_abuse_days int not null default 0;

-- Verrouillé comme rank/global_level/emblem_damage : écriture serveur only.
revoke update (consecutive_abuse_days) on profiles from authenticated;

-- ----------------------------------------------------------------------------
-- 2. Helper partagé : recalcul niveau global + rang (SPEC §5: recompute_levels)
-- ----------------------------------------------------------------------------
create function public.recompute_profile_progress(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_global int;
  v_new_rank   hunter_rank;
begin
  select floor(avg(level))::int into v_new_global
    from user_stats where user_id = p_user_id;
  v_new_rank := public.rank_for_level(v_new_global);

  update profiles
    set global_level = v_new_global, rank = v_new_rank
    where id = p_user_id;
end;
$$;

revoke execute on function public.recompute_profile_progress(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. complete_habit() — ajout bonus journée parfaite ×1.5 (M2)
-- ----------------------------------------------------------------------------
create or replace function public.complete_habit(p_habit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id         uuid := auth.uid();
  v_habit           habits%rowtype;
  v_tz              text;
  v_today           date;
  v_yesterday       date;
  v_iso_weekday     int;
  v_base_xp         int;
  v_multiplier      numeric(4, 2) := 1.0;
  v_xp_earned       int;
  v_streak          streaks%rowtype;
  v_new_current     int;
  v_new_best        int;
  v_stat_level      int;
  v_stat_xp         int;
  v_threshold       int;
  v_scheduled_count int;
  v_completed_before int;
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
  v_iso_weekday := extract(isodow from v_today)::int;

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

  -- Bonus journée parfaite (§3.2, M2) : cette complétion est-elle celle qui
  -- fait passer toutes les habitudes programmées aujourd'hui à 100% ?
  -- Cumulatif avec le multiplicateur streak ci-dessus, cap ×3.
  if exists (
    select 1 from jsonb_array_elements_text(v_habit.schedule -> 'days') e
    where e::int = v_iso_weekday
  ) then
    select count(*) into v_scheduled_count
      from habits h
      where h.user_id = v_user_id and h.active and h.created_at::date <= v_today
        and exists (
          select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
          where e::int = v_iso_weekday
        );

    select count(*) into v_completed_before
      from habit_logs hl
      join habits h2 on h2.id = hl.habit_id
      where hl.user_id = v_user_id and hl.date = v_today and hl.completed_at is not null
        and h2.active and h2.created_at::date <= v_today
        and exists (
          select 1 from jsonb_array_elements_text(h2.schedule -> 'days') e
          where e::int = v_iso_weekday
        );

    if v_scheduled_count > 0 and v_completed_before = v_scheduled_count - 1 then
      v_multiplier := least(3.0, v_multiplier * 1.5);
    end if;
  end if;

  v_xp_earned := round(v_base_xp * v_multiplier);

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, v_multiplier, false);

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

  perform public.recompute_profile_progress(v_user_id);

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'stat', v_habit.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'global_level', (select global_level from profiles where id = v_user_id),
    'rank', (select rank from profiles where id = v_user_id),
    'streak_current', v_new_current,
    'streak_best', v_new_best
  );
end;
$$;

grant execute on function public.complete_habit(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. close_day — Tribunal de minuit pour un user/jour donné
--
-- Non exposée au client (pas de grant execute to authenticated) : c'est un
-- processus système, testé/déclenché uniquement en SQL privilégié / pg_cron.
-- ----------------------------------------------------------------------------
create function public.close_day(p_user_id uuid, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile              profiles%rowtype;
  v_iso_weekday          int := extract(isodow from p_date)::int;
  v_scheduled_count      int;
  v_completed_count      int;
  v_day_rate             numeric;
  v_is_perfect_day       boolean;
  v_completion_rate_7d   numeric;
  v_is_slump             boolean;
  v_is_abuse_day         boolean;
  v_new_consecutive      int;
  v_penalty_multiplier   numeric(4, 2);
  v_habit                record;
  v_base_xp              int;
  v_penalty              int;
  v_streak_global        streaks%rowtype;
  v_new_streak_current   int;
  v_new_streak_best      int;
  v_new_shields          int;
  v_new_emblem           int;
  v_new_global           int;
begin
  -- Idempotence sous concurrence : un seul close_day(user,date) à la fois.
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

  -- Complétion du jour p_date : habitudes actives, programmées ce jour,
  -- déjà créées à cette date (pas de pénalité rétroactive sur une habitude
  -- qui n'existait pas encore).
  select count(*) into v_scheduled_count
    from habits h
    where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
      and exists (
        select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
        where e::int = v_iso_weekday
      );

  select count(*) into v_completed_count
    from habit_logs hl
    join habits h on h.id = hl.habit_id
    where hl.user_id = p_user_id and hl.date = p_date and hl.completed_at is not null
      and h.active and h.created_at::date <= p_date
      and exists (
        select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
        where e::int = v_iso_weekday
      );

  v_day_rate := case when v_scheduled_count = 0 then 1.0
                      else v_completed_count::numeric / v_scheduled_count end;
  v_is_perfect_day := v_day_rate >= 1.0;

  -- Taux de complétion glissant 7 jours (habitudes uniquement — todos = M5).
  select coalesce(
    sum(completed_count)::numeric / nullif(sum(scheduled_count), 0), 1.0
  ) into v_completion_rate_7d
  from (
    select
      (select count(*) from habits h
         where h.user_id = p_user_id and h.active and h.created_at::date <= d::date
           and exists (
             select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
             where e::int = extract(isodow from d::date)::int
           )
      ) as scheduled_count,
      (select count(*) from habit_logs hl
         where hl.user_id = p_user_id and hl.date = d::date and hl.completed_at is not null
      ) as completed_count
    from generate_series(p_date - 6, p_date, interval '1 day') as d
  ) sub;

  v_is_slump := v_completion_rate_7d < 0.40;
  v_is_abuse_day := (not v_is_slump) and (v_day_rate < 0.50);

  -- Escalade (§3.9) : le mode slump remet le compteur à zéro (« on ne juge
  -- pas les mauvaises semaines ») ; un jour >= 50% le remet aussi à zéro.
  v_new_consecutive := case when v_is_abuse_day then v_profile.consecutive_abuse_days + 1
                             else 0 end;

  v_penalty_multiplier := case
    when v_is_slump then 1.0
    when not v_is_abuse_day then 1.0
    when v_new_consecutive >= 3 then 2.0
    when v_new_consecutive = 2 then 1.5
    else 1.0
  end;

  -- Pénalités sur chaque habitude programmée non complétée.
  for v_habit in
    select h.id, h.stat, h.difficulty
    from habits h
    where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
      and exists (
        select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
        where e::int = v_iso_weekday
      )
      and not exists (
        select 1 from habit_logs hl
        where hl.habit_id = h.id and hl.date = p_date and hl.completed_at is not null
      )
  loop
    v_base_xp := case v_habit.difficulty
      when 'easy' then 10
      when 'medium' then 25
      when 'hard' then 50
    end;
    v_penalty := round(v_base_xp * 0.4 * v_penalty_multiplier);

    update user_stats
      set current_xp = greatest(0, current_xp - v_penalty)
      where user_id = p_user_id and stat = v_habit.stat;

    insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
    values (v_habit.id, p_user_id, p_date, null, -v_penalty, v_penalty_multiplier, false);

    insert into streaks (user_id, habit_id, current, best, last_completed_date)
    values (p_user_id, v_habit.id, 0, 0, null)
    on conflict (user_id, habit_id) where habit_id is not null
    do update set current = 0;
  end loop;

  -- Streak global + boucliers (§3.4). Décision actée : bouclier = streak figé.
  select * into v_streak_global from streaks
    where user_id = p_user_id and habit_id is null;

  if v_is_perfect_day then
    v_new_streak_current := v_streak_global.current + 1;
    v_new_streak_best := greatest(v_streak_global.best, v_new_streak_current);
    v_new_shields := case when v_new_streak_current % 10 = 0
                           then least(3, v_streak_global.shields + 1)
                           else v_streak_global.shields end;
  elsif v_streak_global.shields > 0 then
    -- Bouclier consommé : la journée ratée est neutralisée, le streak
    -- ne descend pas mais ne monte pas non plus.
    v_new_streak_current := v_streak_global.current;
    v_new_streak_best := v_streak_global.best;
    v_new_shields := v_streak_global.shields - 1;
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

  -- Malus visible (§3.16) : +1 cran si jour d'abus, -1 cran si parfaite.
  -- Cap à 2 ici : l'état 3 (blason sombre) exige un boss actif (M4).
  v_new_emblem := case
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

  -- Snapshot quotidien (alimente le Fantôme J-30 et le Journal, M6).
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
    'scheduled_count', v_scheduled_count,
    'completed_count', v_completed_count,
    'day_rate', v_day_rate,
    'is_perfect_day', v_is_perfect_day,
    'completion_rate_7d', v_completion_rate_7d,
    'is_slump', v_is_slump,
    'is_abuse_day', v_is_abuse_day,
    'consecutive_abuse_days', v_new_consecutive,
    'penalty_multiplier', v_penalty_multiplier,
    'streak_current', v_new_streak_current,
    'shields', v_new_shields,
    'emblem_damage', v_new_emblem,
    'global_level', v_new_global
  );
end;
$$;

-- Postgres accorde EXECUTE à PUBLIC par défaut à la création d'une fonction :
-- révocation explicite, ce n'est pas un endpoint client (système only).
revoke execute on function public.close_day(uuid, date) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. run_midnight_close — scanne les users dont minuit local vient de passer
-- ----------------------------------------------------------------------------
create function public.run_midnight_close()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_local_time time;
  v_yesterday  date;
begin
  for r in select id, timezone from profiles loop
    v_local_time := (now() at time zone r.timezone)::time;
    if v_local_time < time '00:15' then
      v_yesterday := ((now() at time zone r.timezone)::date) - 1;
      perform public.close_day(r.id, v_yesterday);
    end if;
  end loop;
end;
$$;

revoke execute on function public.run_midnight_close() from public, anon, authenticated;

-- pg_cron : toutes les 15 min, cohérent avec la fenêtre testée ci-dessus.
create extension if not exists pg_cron;
select cron.schedule('midnight-close', '*/15 * * * *', $$select public.run_midnight_close();$$);
