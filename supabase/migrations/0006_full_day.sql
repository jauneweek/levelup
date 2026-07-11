-- ============================================================================
-- LEVELUP — Migration 0006 : Journée complète (M5)
-- Réf : SPEC §3.8 (todos, rituel du soir, morning brief), §3.9 (pénalités —
-- extension aux todos), §3.10 (donjon instantané), §3.16 (malus visible —
-- déjà couvert M2/M4, inchangé ici), §5.
--
-- Contenu :
--   1. Durcissement todos : grants colonne (comme profiles en M1) — le
--      client garde l'écriture sur ses todos (légitime, comme habits) mais
--      ne peut pas fixer completed_at/xp_earned directement, seulement via
--      complete_todo().
--   2. complete_todo() : miroir de complete_habit(), sans streak ni rush
--      (SPEC §3.6 dit explicitement "une habitude" pour le rush) ni
--      progression de quête hebdo (idem, "habitudes de {stat}") — mais
--      éligible à la quête secrète (target_type peut être 'todo', §3.14)
--      et au bonus journée parfaite (§3.8 : 100% habitudes ET todos).
--   3. Trigger rituel du soir : +10 XP PRO à la 1ère todo créée pour le
--      lendemain, un fois par jour de création (§3.8).
--   4. complete_habit() — CREATE OR REPLACE : le calcul "journée parfaite"
--      inclut désormais les todos du jour, pas seulement les habitudes.
--   5. complete_habit_express() : donjon instantané (§3.10) — 50% XP,
--      streak préservé, cap 2/jour (habit_logs.is_express).
--   6. close_day() — CREATE OR REPLACE : taux du jour / taux 7j / boucle de
--      pénalités incluent désormais les todos.
--   7. run_daily_tick() — CREATE OR REPLACE : ajoute l'annonce morning_brief
--      (08:00 local, mêmes templates seedés en M0).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Durcissement todos — grants colonne (client garde la main sur la
--    définition de la todo, jamais sur completed_at/xp_earned)
-- ----------------------------------------------------------------------------
revoke insert, update on todos from authenticated;
grant insert (user_id, title, stat, difficulty, date, deadline_time) on todos to authenticated;
grant update (title, stat, difficulty, date, deadline_time) on todos to authenticated;

-- ----------------------------------------------------------------------------
-- 2. complete_todo() — cœur de la boucle de jeu pour les todos (M5)
-- ----------------------------------------------------------------------------
create function public.complete_todo(p_todo_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id          uuid := auth.uid();
  v_todo             todos%rowtype;
  v_tz               text;
  v_today            date;
  v_iso_weekday      int;
  v_base_xp          int;
  v_multiplier       numeric(4, 2) := 1.0;
  v_xp_earned        int;
  v_stat_level       int;
  v_stat_xp          int;
  v_threshold        int;
  v_scheduled_count  int;
  v_completed_before int;
  v_potion_active    boolean;
  v_secret           secret_quests%rowtype;
  v_secret_result    jsonb := null;
  v_item             items;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_todo from todos where id = p_todo_id and user_id = v_user_id;
  if not found then
    raise exception 'todo not found or not owned by user' using errcode = '42501';
  end if;

  select timezone into v_tz from profiles where id = v_user_id;
  v_today := (now() at time zone v_tz)::date;
  v_iso_weekday := extract(isodow from v_today)::int;

  if v_todo.date <> v_today then
    raise exception 'todo is not schedulable today' using errcode = 'P0001';
  end if;

  if v_todo.completed_at is not null then
    return jsonb_build_object('already_completed', true, 'date', v_today);
  end if;

  v_base_xp := case v_todo.difficulty
    when 'easy' then 10
    when 'medium' then 25
    when 'hard' then 50
  end;

  -- Quête secrète (§3.14) : peut cibler une todo comme une habitude.
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

  -- Bonus journée parfaite (§3.2/§3.8) : 100% des habitudes ET todos.
  select exists (
    select 1 from events_log
    where user_id = v_user_id and date = v_today and event_type = 'potion'
  ) into v_potion_active;

  select
    (select count(*) from habits h
       where h.user_id = v_user_id and h.active and h.created_at::date <= v_today
         and exists (
           select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t where t.user_id = v_user_id and t.date = v_today)
  into v_scheduled_count;

  select
    (select count(*) from habit_logs hl
       join habits h2 on h2.id = hl.habit_id
       where hl.user_id = v_user_id and hl.date = v_today and hl.completed_at is not null
         and h2.active and h2.created_at::date <= v_today
         and exists (
           select 1 from jsonb_array_elements_text(h2.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t
         where t.user_id = v_user_id and t.date = v_today and t.completed_at is not null
           and t.id <> p_todo_id)
  into v_completed_before;

  if v_scheduled_count > 0 and v_completed_before = v_scheduled_count - 1 then
    v_multiplier := v_multiplier * (case when v_potion_active then 3.0 else 1.5 end);
  end if;

  v_multiplier := least(3.0, v_multiplier);
  v_xp_earned := round(v_base_xp * v_multiplier);

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

  perform public.recompute_profile_progress(v_user_id);

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'stat', v_todo.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'global_level', (select global_level from profiles where id = v_user_id),
    'rank', (select rank from profiles where id = v_user_id),
    'secret_quest_revealed', v_secret_result
  );
end;
$$;

revoke execute on function public.complete_todo(uuid) from public, anon, authenticated;
grant execute on function public.complete_todo(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Rituel du soir (§3.8) : +10 XP PRO à la 1ère todo créée pour demain
-- ----------------------------------------------------------------------------
create function public.grant_evening_ritual_xp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tz         text;
  v_today      date;
  v_stat_level int;
  v_stat_xp    int;
  v_threshold  int;
begin
  select timezone into v_tz from profiles where id = new.user_id;
  v_today := (now() at time zone v_tz)::date;

  -- Récompense la planification (créer la todo de demain), pas la todo
  -- elle-même : une seule fois par jour de création, quel que soit le
  -- nombre de todos planifiées dans la foulée.
  if new.date = v_today + 1 and not exists (
    select 1 from todos
    where user_id = new.user_id and date = new.date and id <> new.id
      and (created_at at time zone v_tz)::date = v_today
  ) then
    select level, current_xp into v_stat_level, v_stat_xp
      from user_stats where user_id = new.user_id and stat = 'PRO'
      for update;

    v_stat_xp := v_stat_xp + 10;
    loop
      v_threshold := xp_to_next_level(v_stat_level);
      exit when v_stat_xp < v_threshold;
      v_stat_xp := v_stat_xp - v_threshold;
      v_stat_level := v_stat_level + 1;
    end loop;

    update user_stats set level = v_stat_level, current_xp = v_stat_xp
      where user_id = new.user_id and stat = 'PRO';

    perform public.recompute_profile_progress(new.user_id);
  end if;

  return new;
end;
$$;

revoke execute on function public.grant_evening_ritual_xp() from public, anon, authenticated;

create trigger on_todo_created_evening_ritual
  after insert on todos
  for each row execute function public.grant_evening_ritual_xp();

-- ----------------------------------------------------------------------------
-- 4. complete_habit() — CREATE OR REPLACE : journée parfaite inclut todos
-- ----------------------------------------------------------------------------
create or replace function public.complete_habit(p_habit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id          uuid := auth.uid();
  v_habit            habits%rowtype;
  v_tz               text;
  v_today            date;
  v_yesterday        date;
  v_iso_weekday      int;
  v_local_time       time;
  v_base_xp          int;
  v_multiplier       numeric(4, 2) := 1.0;
  v_xp_earned        int;
  v_streak           streaks%rowtype;
  v_new_current      int;
  v_new_best         int;
  v_stat_level       int;
  v_stat_xp          int;
  v_threshold        int;
  v_scheduled_count  int;
  v_completed_before int;
  v_potion_active    boolean;
  v_rush_habit_id    uuid;
  v_secret           secret_quests%rowtype;
  v_secret_result    jsonb := null;
  v_item             items;
  v_chest            events_log%rowtype;
  v_today_completed  int;
  v_quest            record;
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
  v_local_time := (now() at time zone v_tz)::time;

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

  -- Heure de rush (§3.6) : l'habitude tirée au sort vaut x2 avant midi.
  select payload ->> 'habit_id' into v_rush_habit_id
    from events_log
    where user_id = v_user_id and date = v_today and event_type = 'rush';

  if v_rush_habit_id is not null and v_rush_habit_id::uuid = p_habit_id
     and v_local_time < time '12:00' then
    v_multiplier := v_multiplier * 2;
  end if;

  -- Quête secrète (§3.14) : révélée seulement à la complétion de la bonne
  -- habitude, jamais avant.
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

  -- Bonus journée parfaite (§3.2/§3.8, M5) : x1.5 sur la dernière habitude
  -- OU todo du jour, x2 en plus si Potion active — cumulé, cap x3. Le
  -- décompte inclut désormais les todos du jour (100% habitudes ET todos).
  select exists (
    select 1 from events_log
    where user_id = v_user_id and date = v_today and event_type = 'potion'
  ) into v_potion_active;

  select
    (select count(*) from habits h
       where h.user_id = v_user_id and h.active and h.created_at::date <= v_today
         and exists (
           select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t where t.user_id = v_user_id and t.date = v_today)
  into v_scheduled_count;

  select
    (select count(*) from habit_logs hl
       join habits h2 on h2.id = hl.habit_id
       where hl.user_id = v_user_id and hl.date = v_today and hl.completed_at is not null
         and h2.active and h2.created_at::date <= v_today
         and exists (
           select 1 from jsonb_array_elements_text(h2.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t
         where t.user_id = v_user_id and t.date = v_today and t.completed_at is not null)
  into v_completed_before;

  if v_scheduled_count > 0 and v_completed_before = v_scheduled_count - 1 then
    v_multiplier := v_multiplier * (case when v_potion_active then 3.0 else 1.5 end);
  end if;

  v_multiplier := least(3.0, v_multiplier);
  v_xp_earned := round(v_base_xp * v_multiplier);

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, v_multiplier, false);

  -- Coffre mystère (§3.6) : condition = 3 habitudes complétées aujourd'hui
  -- (la SPEC dit "habitudes", pas todos — décompte inchangé). Récompense
  -- accordée une seule fois (events_log.resolved).
  select * into v_chest from events_log
    where user_id = v_user_id and date = v_today and event_type = 'chest' and not resolved;

  if found then
    select count(*) into v_today_completed
      from habit_logs
      where user_id = v_user_id and date = v_today and completed_at is not null;

    if v_today_completed >= 3 then
      update events_log set resolved = true where id = v_chest.id;
      perform public.grant_random_item(v_user_id, 'common');
    end if;
  end if;

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

  -- Progression des quêtes hebdo actives correspondant à la stat (§3.5 :
  -- "habitudes de {stat}" — les todos n'y contribuent pas, lecture littérale).
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
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'stat', v_habit.stat,
    'stat_level', v_stat_level,
    'stat_xp', v_stat_xp,
    'global_level', (select global_level from profiles where id = v_user_id),
    'rank', (select rank from profiles where id = v_user_id),
    'streak_current', v_new_current,
    'streak_best', v_new_best,
    'secret_quest_revealed', v_secret_result
  );
end;
$$;

grant execute on function public.complete_habit(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. complete_habit_express() — Donjon Instantané (§3.10)
--    50% XP, streak préservé, compte pour la journée parfaite. Pas de
--    rush/potion/secret/quête hebdo : version délibérément minimale (c'est
--    une soupape anti-procrastination, pas un chemin pour cumuler des
--    bonus). Cap 2/jour, compté via habit_logs.is_express.
-- ----------------------------------------------------------------------------
create function public.complete_habit_express(p_habit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id       uuid := auth.uid();
  v_habit         habits%rowtype;
  v_tz            text;
  v_today         date;
  v_yesterday     date;
  v_base_xp       int;
  v_xp_earned     int;
  v_streak        streaks%rowtype;
  v_new_current   int;
  v_new_best      int;
  v_stat_level    int;
  v_stat_xp       int;
  v_threshold     int;
  v_express_count int;
  v_quest         record;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_habit from habits where id = p_habit_id and user_id = v_user_id;
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

  if exists (select 1 from habit_logs where habit_id = p_habit_id and date = v_today) then
    return jsonb_build_object('already_completed', true, 'date', v_today);
  end if;

  select count(*) into v_express_count
    from habit_logs where user_id = v_user_id and date = v_today and is_express;

  if v_express_count >= 2 then
    return jsonb_build_object('express_limit_reached', true);
  end if;

  v_base_xp := case v_habit.difficulty
    when 'easy' then 10 when 'medium' then 25 when 'hard' then 50
  end;
  v_xp_earned := round(v_base_xp * 0.5);

  select * into v_streak from streaks where user_id = v_user_id and habit_id = p_habit_id;
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

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, 0.5, true);

  select level, current_xp into v_stat_level, v_stat_xp
    from user_stats where user_id = v_user_id and stat = v_habit.stat
    for update;

  v_stat_xp := v_stat_xp + v_xp_earned;
  loop
    v_threshold := xp_to_next_level(v_stat_level);
    exit when v_stat_xp < v_threshold;
    v_stat_xp := v_stat_xp - v_threshold;
    v_stat_level := v_stat_level + 1;
  end loop;

  update user_stats set level = v_stat_level, current_xp = v_stat_xp
    where user_id = v_user_id and stat = v_habit.stat;

  perform public.recompute_profile_progress(v_user_id);

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
    'xp_earned', v_xp_earned,
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

revoke execute on function public.complete_habit_express(uuid) from public, anon, authenticated;
grant execute on function public.complete_habit_express(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. close_day() — CREATE OR REPLACE : todos dans taux/pénalités (M5)
-- ----------------------------------------------------------------------------
create or replace function public.close_day(p_user_id uuid, p_date date)
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
  v_cursed_active        boolean;
  v_habit                record;
  v_todo                 record;
  v_base_xp              int;
  v_penalty              int;
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

  -- Taux du jour (§3.8, M5) : habitudes ET todos programmées ce jour-là.
  select
    (select count(*) from habits h
       where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
         and exists (
           select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t where t.user_id = p_user_id and t.date = p_date)
  into v_scheduled_count;

  select
    (select count(*) from habit_logs hl
       join habits h on h.id = hl.habit_id
       where hl.user_id = p_user_id and hl.date = p_date and hl.completed_at is not null
         and h.active and h.created_at::date <= p_date
         and exists (
           select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
           where e::int = v_iso_weekday
         ))
    + (select count(*) from todos t
         where t.user_id = p_user_id and t.date = p_date and t.completed_at is not null)
  into v_completed_count;

  v_day_rate := case when v_scheduled_count = 0 then 1.0
                      else v_completed_count::numeric / v_scheduled_count end;
  v_is_perfect_day := v_day_rate >= 1.0;

  -- Taux glissant 7 jours : habitudes ET todos.
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
      ) + (select count(*) from todos t where t.user_id = p_user_id and t.date = d::date)
      as scheduled_count,
      (select count(*) from habit_logs hl
         where hl.user_id = p_user_id and hl.date = d::date and hl.completed_at is not null
      ) + (select count(*) from todos t
             where t.user_id = p_user_id and t.date = d::date and t.completed_at is not null)
      as completed_count
    from generate_series(p_date - 6, p_date, interval '1 day') as d
  ) sub;

  v_is_slump := v_completion_rate_7d < 0.40;
  v_is_abuse_day := (not v_is_slump) and (v_day_rate < 0.50);

  v_new_consecutive := case when v_is_abuse_day then v_profile.consecutive_abuse_days + 1
                             else 0 end;

  v_penalty_multiplier := case
    when v_is_slump then 1.0
    when not v_is_abuse_day then 1.0
    when v_new_consecutive >= 3 then 2.0
    when v_new_consecutive = 2 then 1.5
    else 1.0
  end;

  -- Jour maudit (§3.6) : pénalités doublées.
  select exists (
    select 1 from events_log
    where user_id = p_user_id and date = p_date and event_type = 'cursed'
  ) into v_cursed_active;
  if v_cursed_active then
    v_penalty_multiplier := v_penalty_multiplier * 2;
  end if;

  -- Pénalités sur les habitudes ratées.
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

  -- Pénalités sur les todos ratées (§3.8/§3.9, M5) : même formule, pas de
  -- streak (les todos n'en ont pas). L'audit de la pénalité vit sur la
  -- todo elle-même (xp_earned négatif), pas de table de log dédiée.
  for v_todo in
    select id, stat, difficulty from todos
    where user_id = p_user_id and date = p_date and completed_at is null
  loop
    v_base_xp := case v_todo.difficulty
      when 'easy' then 10
      when 'medium' then 25
      when 'hard' then 50
    end;
    v_penalty := round(v_base_xp * 0.4 * v_penalty_multiplier);

    update user_stats
      set current_xp = greatest(0, current_xp - v_penalty)
      where user_id = p_user_id and stat = v_todo.stat;

    update todos set xp_earned = -v_penalty where id = v_todo.id;
  end loop;

  -- Streak global + boucliers (§3.4).
  select * into v_streak_global from streaks
    where user_id = p_user_id and habit_id is null;
  v_old_streak_current := v_streak_global.current;

  if v_is_perfect_day then
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

  -- Quête de rédemption (§3.5).
  if (not v_is_perfect_day) and v_streak_global.shields = 0
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
    else
      update quests set progress = 0 where id = v_redemption.id;
    end if;
  end if;

  -- Titres de streak (§3.4).
  for i in 1..array_length(v_thresholds, 1) loop
    if v_new_streak_current >= v_thresholds[i] then
      v_unlocked := public.unlock_title_if_new(p_user_id, v_titles[i]);
      if v_unlocked then
        perform public.enqueue_notification(
          p_user_id, 'streak_milestone',
          jsonb_build_object('streak', v_new_streak_current, 'title_next', v_titles[i])
        );
      end if;
    end if;
  end loop;

  -- Boss de la Procrastination (§3.7).
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
    'global_level', v_new_global,
    'boss_active', v_boss_active_after,
    'boss_hp', case when v_boss.id is not null then v_boss.hp else null end,
    'boss_status', v_boss.status
  );
end;
$$;

revoke execute on function public.close_day(uuid, date) from public, anon, authenticated;

-- Annonce du morning brief (§3.8) : extrait en fonction dédiée (comme
-- draw_daily_event/draw_secret_quest) pour rester testable indépendamment
-- du scan par fuseau de run_daily_tick.
create function public.send_morning_brief(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rank   hunter_rank;
  v_streak int;
begin
  select rank into v_rank from profiles where id = p_user_id;

  select current into v_streak from streaks
    where user_id = p_user_id and habit_id is null;

  perform public.enqueue_notification(
    p_user_id, 'morning_brief',
    jsonb_build_object('rank', v_rank, 'streak', coalesce(v_streak, 0))
  );
end;
$$;

revoke execute on function public.send_morning_brief(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 7. run_daily_tick() — CREATE OR REPLACE : ajoute l'annonce morning_brief
-- ----------------------------------------------------------------------------
create or replace function public.run_daily_tick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r             record;
  v_local_time  time;
  v_local_today date;
begin
  for r in select id, timezone from profiles loop
    v_local_time := (now() at time zone r.timezone)::time;
    if v_local_time >= time '08:00' and v_local_time < time '08:15' then
      v_local_today := (now() at time zone r.timezone)::date;
      perform public.draw_daily_event(r.id, v_local_today);
      perform public.draw_secret_quest(r.id, v_local_today);
      perform public.send_morning_brief(r.id);
    end if;
  end loop;
end;
$$;

revoke execute on function public.run_daily_tick() from public, anon, authenticated;
