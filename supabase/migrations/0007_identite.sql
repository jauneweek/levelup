-- ============================================================================
-- LEVELUP — Migration 0007 : Identité (M6)
-- Réf : SPEC §3.11 (Armée des Ombres), §3.12 (Fantôme — lecture seule, le
-- duel est V1.5 hors scope), §3.15 (Journal du Chasseur), §5.
--
-- Portée délibérée (roadmap M6 vs M7) : "Animations rang-up/extraction" est
-- explicitement assignée à M7 dans la roadmap (comme le rank-up, déjà
-- différé depuis M1). M6 construit la mécanique d'extraction/évolution des
-- Ombres et sa révélation simple (retour JSON), pas le rituel plein écran.
--
-- Contenu :
--   1. check_shadow_extraction() : une Ombre par habitude (pas 4 lignes par
--      grade) qui évolue de grade au fil des seuils de complétions
--      (100/250/500/1000). shadows/journal_entries/daily_snapshots déjà
--      durcis en lecture seule depuis M4 — rien à refaire ici.
--   2. Bonus XP passif des Ombres (+2%/Ombre sur sa stat, cap +10%) :
--      couche séparée appliquée APRÈS le cap x3 existant (SPEC §3.2 ne le
--      liste pas parmi les 3 multiplicateurs capés — décision actée).
--   3. close_day() — CREATE OR REPLACE : horodate unlocked_at sur p_date
--      plutôt que now() (correction, cf. commentaire en section 3).
--   4. complete_habit()/complete_habit_express()/complete_todo() — CREATE OR
--      REPLACE : branchent l'extraction (habitudes seulement) et le bonus
--      passif (habitudes ET todos, bonus stat-wide).
--   5. generate_weekly_journal() : récap hebdo (quêtes, XP net, dégâts
--      boss, Ombres extraites, titres débloqués, taux vs semaine
--      précédente, progression vs Fantôme). Lit daily_snapshots du dernier
--      jour clos (dimanche 20h : le jour même n'a pas encore de snapshot,
--      calculé par close_day à minuit).
--   6. run_weekly_tick() — CREATE OR REPLACE : ajoute le scan dimanche 20h.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. check_shadow_extraction — une Ombre par habitude, grade évolutif
-- ----------------------------------------------------------------------------
create function public.check_shadow_extraction(p_user_id uuid, p_habit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_completions int;
  v_habit       habits%rowtype;
  v_shadow      shadows%rowtype;
  v_grade       shadow_grade;
begin
  select count(*) into v_completions
    from habit_logs where habit_id = p_habit_id and completed_at is not null;

  v_grade := case
    when v_completions >= 1000 then 'marechal'
    when v_completions >= 500 then 'general'
    when v_completions >= 250 then 'chevalier'
    when v_completions >= 100 then 'soldat'
    else null
  end;

  if v_grade is null then
    return;
  end if;

  select * into v_shadow from shadows where habit_id = p_habit_id;

  if not found then
    select * into v_habit from habits where id = p_habit_id;
    insert into shadows (user_id, habit_id, name, grade, completions_at_extraction)
    values (p_user_id, p_habit_id, v_habit.name, v_grade, v_completions);
  elsif v_shadow.grade <> v_grade then
    -- Évolution de grade uniquement (les seuils de complétions ne
    -- redescendent jamais : jamais de rétrogradation possible).
    update shadows set grade = v_grade, completions_at_extraction = v_completions
      where id = v_shadow.id;
  end if;
end;
$$;

revoke execute on function public.check_shadow_extraction(uuid, uuid) from public, anon, authenticated;

-- Bonus XP passif (§3.11) : +2% par Ombre sur sa stat, cap +10%/stat.
-- Stat-wide (toute XP gagnée sur cette stat en bénéficie, pas seulement
-- l'habitude qui a produit l'Ombre — "chaque Ombre donne +2% XP... sur sa
-- stat", lecture du bonus comme un buff permanent de maîtrise du domaine).
create function public.shadow_xp_bonus_multiplier(p_user_id uuid, p_stat stat_type)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select 1 + least(0.10, count(*) * 0.02)
  from shadows s
  join habits h on h.id = s.habit_id
  where h.user_id = p_user_id and h.stat = p_stat;
$$;

revoke execute on function public.shadow_xp_bonus_multiplier(uuid, stat_type) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. close_day() — CREATE OR REPLACE : fixe unlocked_at à la date traitée
--    (p_date), pas à l'instant réel d'exécution. Sans ce correctif, un
--    rattrapage (cron en retard, ou tout appel sur une date passée) horodate
--    le déblocage du titre à "maintenant" plutôt qu'au jour réellement
--    atteint — ça fausse silencieusement le comptage "titres débloqués
--    cette semaine" du Journal (§3.15). Reste identique à la version M5
--    sinon.
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

  -- Taux du jour : habitudes ET todos programmées ce jour-là.
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

  -- Pénalités sur les todos ratées : même formule, pas de streak.
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

-- ----------------------------------------------------------------------------
-- 3. complete_habit() — CREATE OR REPLACE : extraction + bonus passif (M6)
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
  v_shadow_bonus     numeric(4, 2);
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

  -- Bonus journée parfaite (§3.2/§3.8) : x1.5 sur la dernière habitude OU
  -- todo du jour, x2 en plus si Potion active — cumulé, cap x3.
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

  -- Bonus passif des Ombres (§3.11, M6) : couche séparée, hors du cap x3
  -- (pas listé parmi les 3 multiplicateurs capés du §3.2).
  v_shadow_bonus := public.shadow_xp_bonus_multiplier(v_user_id, v_habit.stat);

  v_xp_earned := round(v_base_xp * v_multiplier * v_shadow_bonus);

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, v_multiplier, false);

  perform public.check_shadow_extraction(v_user_id, p_habit_id);

  -- Coffre mystère (§3.6) : condition = 3 habitudes complétées aujourd'hui
  -- (la SPEC dit "habitudes", pas todos). Récompense accordée une seule
  -- fois (events_log.resolved).
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

  -- Progression des quêtes hebdo actives correspondant à la stat.
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
    'shadow_bonus', v_shadow_bonus,
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
-- 4. complete_habit_express() — CREATE OR REPLACE : extraction + bonus (M6)
-- ----------------------------------------------------------------------------
create or replace function public.complete_habit_express(p_habit_id uuid)
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
  v_shadow_bonus  numeric(4, 2);
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
  v_shadow_bonus := public.shadow_xp_bonus_multiplier(v_user_id, v_habit.stat);
  v_xp_earned := round(v_base_xp * 0.5 * v_shadow_bonus);

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

  perform public.check_shadow_extraction(v_user_id, p_habit_id);

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
    'shadow_bonus', v_shadow_bonus,
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
-- 5. complete_todo() — CREATE OR REPLACE : bonus passif des Ombres (M6)
--    Pas d'extraction (les Ombres viennent des habitudes, §3.11), mais le
--    bonus est stat-wide donc une todo en bénéficie aussi.
-- ----------------------------------------------------------------------------
create or replace function public.complete_todo(p_todo_id uuid)
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
  v_shadow_bonus     numeric(4, 2);
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

  perform public.recompute_profile_progress(v_user_id);

  return jsonb_build_object(
    'already_completed', false,
    'xp_earned', v_xp_earned,
    'multiplier', v_multiplier,
    'shadow_bonus', v_shadow_bonus,
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
-- 6. generate_weekly_journal() — récap hebdo (§3.15)
--    Lit le dernier jour clos (semaine se termine dimanche, mais le
--    snapshot du dimanche lui-même n'existe qu'après minuit) : on compare
--    donc sur le samedi (v_week_end - 1) pour tout ce qui vient de
--    daily_snapshots, tandis que les compteurs bruts (quêtes, XP) lisent
--    habit_logs/todos directement jusqu'à l'instant présent.
-- ----------------------------------------------------------------------------
create function public.generate_weekly_journal(p_user_id uuid, p_week_start date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_end          date := p_week_start + 6;
  v_latest_closed_day date := p_week_start + 5; -- samedi
  v_quests_completed  int;
  v_xp_gained         int;
  v_xp_lost           int;
  v_boss_damage       int;
  v_shadows_extracted int;
  v_titles_unlocked   int;
  v_completion_rate   numeric;
  v_prev_completion_rate numeric;
  v_ghost_delta       int;
  v_daily_breakdown   jsonb;
begin
  if exists (
    select 1 from journal_entries where user_id = p_user_id and week_start = p_week_start
  ) then
    return;
  end if;

  select
    coalesce(sum(xp_earned) filter (where xp_earned > 0), 0),
    coalesce(-sum(xp_earned) filter (where xp_earned < 0), 0),
    count(*) filter (where completed_at is not null)
  into v_xp_gained, v_xp_lost, v_quests_completed
  from (
    select xp_earned, completed_at from habit_logs
      where user_id = p_user_id and date between p_week_start and v_week_end
    union all
    select xp_earned, completed_at from todos
      where user_id = p_user_id and date between p_week_start and v_week_end
  ) x;

  select count(*) into v_boss_damage
    from notification_queue
    where user_id = p_user_id and trigger_type = 'boss_damage'
      and created_at::date between p_week_start and v_week_end;

  select count(*) into v_shadows_extracted
    from shadows
    where user_id = p_user_id and extracted_at::date between p_week_start and v_week_end;

  select count(*) into v_titles_unlocked
    from user_titles
    where user_id = p_user_id and unlocked_at::date between p_week_start and v_week_end;

  select completion_rate_7d into v_completion_rate
    from daily_snapshots where user_id = p_user_id and date = v_latest_closed_day;

  select completion_rate_7d into v_prev_completion_rate
    from daily_snapshots where user_id = p_user_id and date = v_latest_closed_day - 7;

  select ds_now.global_level - ds_ghost.global_level into v_ghost_delta
    from daily_snapshots ds_now
    left join daily_snapshots ds_ghost
      on ds_ghost.user_id = ds_now.user_id and ds_ghost.date = ds_now.date - 30
    where ds_now.user_id = p_user_id and ds_now.date = v_latest_closed_day;

  select jsonb_object_agg(to_char(d.date, 'YYYY-MM-DD'), d.completed) into v_daily_breakdown
  from (
    select gs.date,
      (select count(*) from habit_logs hl where hl.user_id = p_user_id and hl.date = gs.date and hl.completed_at is not null)
      + (select count(*) from todos t where t.user_id = p_user_id and t.date = gs.date and t.completed_at is not null)
      as completed
    from generate_series(p_week_start, v_week_end, interval '1 day') as gs(date)
  ) d;

  insert into journal_entries (user_id, week_start, payload)
  values (
    p_user_id, p_week_start,
    jsonb_build_object(
      'quests_completed', v_quests_completed,
      'xp_gained', v_xp_gained,
      'xp_lost', v_xp_lost,
      'boss_damage', v_boss_damage,
      'shadows_extracted', v_shadows_extracted,
      'titles_unlocked', v_titles_unlocked,
      'completion_rate', coalesce(v_completion_rate, 0),
      'completion_rate_prev', coalesce(v_prev_completion_rate, 0),
      'ghost_delta', v_ghost_delta,
      'daily_breakdown', coalesce(v_daily_breakdown, '{}'::jsonb)
    )
  );
end;
$$;

revoke execute on function public.generate_weekly_journal(uuid, date) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 7. run_weekly_tick() — CREATE OR REPLACE : ajoute le scan dimanche 20h
-- ----------------------------------------------------------------------------
create or replace function public.run_weekly_tick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r             record;
  v_local_time  time;
  v_local_today date;
  v_iso_weekday int;
begin
  for r in select id, timezone from profiles loop
    v_local_time := (now() at time zone r.timezone)::time;
    v_local_today := (now() at time zone r.timezone)::date;
    v_iso_weekday := extract(isodow from v_local_today)::int;

    if v_iso_weekday = 1 and v_local_time >= time '00:00' and v_local_time < time '00:15' then
      perform public.generate_weekly_quests(r.id, v_local_today);
    end if;

    if v_iso_weekday = 7 and v_local_time >= time '20:00' and v_local_time < time '20:15' then
      perform public.generate_weekly_journal(r.id, v_local_today - 6);
    end if;
  end loop;
end;
$$;

revoke execute on function public.run_weekly_tick() from public, anon, authenticated;
