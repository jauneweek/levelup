-- ============================================================================
-- LEVELUP — Migration 0005 : Meta-game (M4)
-- Réf : SPEC §3.4 (titres), §3.5 (quêtes), §3.6 (événements aléatoires),
-- §3.7 (boss), §3.14 (quête secrète), §3.16 (malus visible état 3), §5.
--
-- Portée notifications (roadmap M4) : boss_spawn/damage/heal/defeat/deadline,
-- event_potion/chest/rush/cursed, streak_milestone, streak_shield,
-- redemption — tous déjà dans le seed (M0), câblés ici. Restent dormants
-- (hors scope M4) : penalty, perfect_day, level_up, rank_up, morning_brief,
-- streak_progress — pas demandés par le critère de done M4, seront câblés
-- avec leurs mécaniques respectives (M5+ : rapport quotidien, rang-up...).
-- La quête secrète n'a pas de trigger de notification dans le seed : sa
-- révélation est instantanée à la complétion (retour JSON de
-- complete_habit), ce qui colle mieux à la SPEC ("révélé qu'à la
-- complétion") qu'un push potentiellement décalé de 5 min (cron).
--
-- Contenu :
--   1. Durcissement RLS — quests/user_items/user_titles/boss_fights/
--      events_log/secret_quests/daily_snapshots/shadows/journal_entries
--      étaient encore sur la policy M0 "for all" (trou anti-triche : un
--      client aurait pu fabriquer sa propre progression de quête, ses PV de
--      boss, ses titres...). Même correction que M1 (user_stats/streaks) et
--      M3 (notification_log).
--   2. Colonnes boss_fights : spawned_on (date locale déjà calculée par
--      close_day, évite tout piège de fuseau sur un cast direct de
--      timestamptz) + deadline_notified (idempotence de l'alerte à 3 jours).
--   3. notification_queue — file d'annonces événementielles. Les triggers
--      T-30/T-15 restent gérés par get_due_notifications (M3, échéances) ;
--      cette file couvre tout ce qui n'est pas un compte à rebours.
--   4. Helpers de récompense : unlock_title_if_new, grant_random_item,
--      enqueue_notification, apply_quest_reward.
--   5. close_day() — CREATE OR REPLACE : boss (spawn/dégâts/soin/défaite/
--      timeout/deadline), titres de streak, quête de rédemption, malus
--      visible état 3, pénalités doublées si Jour maudit actif.
--   6. draw_daily_event() / draw_secret_quest() / run_daily_tick() — tirage
--      quotidien (scan 08:00 par fuseau, même pattern que run_midnight_close).
--   7. generate_weekly_quests() / run_weekly_tick() — 2 quêtes hebdo
--      (lundi 00:00 par fuseau).
--   8. complete_habit() — CREATE OR REPLACE : multiplicateurs Potion/Rush,
--      coffre mystère, révélation quête secrète, progression quêtes hebdo.
--   9. get_due_queued_notifications() / record_queue_notification_sent().
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DURCISSEMENT RLS — tables de méta-jeu en lecture seule pour le client
--    (même trou de triche que user_stats/habit_logs/streaks en M1 : la
--    policy M0 "for all" laissait le client écrire directement).
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'quests', 'user_items', 'user_titles', 'boss_fights', 'events_log',
    'secret_quests', 'daily_snapshots', 'shadows', 'journal_entries'
  ]
  loop
    execute format('drop policy %1$I_owner on public.%1$I;', t);
    execute format(
      'create policy %1$I_read on public.%1$I for select to authenticated '
      || 'using (user_id = auth.uid());', t
    );
    execute format('revoke insert, update, delete on public.%1$I from authenticated;', t);
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Colonnes boss_fights (§3.7)
-- ----------------------------------------------------------------------------
alter table boss_fights
  add column spawned_on date,
  add column deadline_notified boolean not null default false;

-- ----------------------------------------------------------------------------
-- 3. notification_queue — file d'annonces événementielles
-- ----------------------------------------------------------------------------
create table notification_queue (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles (id) on delete cascade,
  trigger_type text not null,
  vars         jsonb not null default '{}'::jsonb,
  habit_id     uuid references habits (id) on delete set null,
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);

alter table notification_queue enable row level security;

create policy notification_queue_read on notification_queue
  for select to authenticated using (user_id = auth.uid());

-- Table créée après le grant global de M0 ("on all tables") : elle n'en
-- hérite pas rétroactivement, contrairement aux tables durcies au-dessus
-- (déjà présentes en M0). La policy seule ne suffit pas sans ce GRANT de
-- base — sinon authenticated n'a aucun privilège SELECT sous-jacent et la
-- policy ne s'applique jamais.
grant select on notification_queue to authenticated;

create index notification_queue_pending_idx on notification_queue (created_at)
  where sent_at is null;

-- ----------------------------------------------------------------------------
-- 4. Helpers de récompense
-- ----------------------------------------------------------------------------
create function public.enqueue_notification(
  p_user_id uuid, p_trigger_type text, p_vars jsonb, p_habit_id uuid default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notification_queue (user_id, trigger_type, vars, habit_id)
  values (p_user_id, p_trigger_type, p_vars, p_habit_id);
$$;

revoke execute on function public.enqueue_notification(uuid, text, jsonb, uuid) from public, anon, authenticated;

-- Débloque un titre s'il ne l'est pas déjà. Retourne true seulement si
-- nouvellement débloqué (gate les notifications streak_milestone).
create function public.unlock_title_if_new(p_user_id uuid, p_title_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title_id uuid;
begin
  select id into v_title_id from titles where name = p_title_name;
  if v_title_id is null then
    return false;
  end if;

  insert into user_titles (user_id, title_id)
  values (p_user_id, v_title_id)
  on conflict (user_id, title_id) do nothing;

  return found;
end;
$$;

revoke execute on function public.unlock_title_if_new(uuid, text) from public, anon, authenticated;

-- Accorde un item aléatoire d'une rareté donnée (empile si déjà possédé).
create function public.grant_random_item(p_user_id uuid, p_rarity text)
returns items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item items%rowtype;
begin
  select * into v_item from items
    where rarity = p_rarity
    order by random()
    limit 1;

  if v_item.id is null then
    return null;
  end if;

  insert into user_items (user_id, item_id, quantity)
  values (p_user_id, v_item.id, 1)
  on conflict (user_id, item_id)
  do update set quantity = user_items.quantity + 1;

  return v_item;
end;
$$;

revoke execute on function public.grant_random_item(uuid, text) from public, anon, authenticated;

-- Accorde la récompense d'une quête (XP bonus ou item cosmétique, §3.5).
create function public.apply_quest_reward(p_user_id uuid, p_quest_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest quests%rowtype;
  v_stat  stat_type;
  v_amount int;
  v_lvl   int;
  v_xp    int;
  v_thr   int;
begin
  select * into v_quest from quests where id = p_quest_id and user_id = p_user_id;
  if not found then
    return;
  end if;

  if v_quest.reward ->> 'type' = 'xp_bonus' then
    v_stat := (v_quest.reward ->> 'stat')::stat_type;
    v_amount := (v_quest.reward ->> 'amount')::int;

    select level, current_xp into v_lvl, v_xp
      from user_stats where user_id = p_user_id and stat = v_stat
      for update;

    v_xp := v_xp + v_amount;
    loop
      v_thr := xp_to_next_level(v_lvl);
      exit when v_xp < v_thr;
      v_xp := v_xp - v_thr;
      v_lvl := v_lvl + 1;
    end loop;

    update user_stats set level = v_lvl, current_xp = v_xp
      where user_id = p_user_id and stat = v_stat;

    perform public.recompute_profile_progress(p_user_id);
  elsif v_quest.reward ->> 'type' = 'item' then
    perform public.grant_random_item(p_user_id, coalesce(v_quest.reward ->> 'rarity', 'common'));
  end if;
end;
$$;

revoke execute on function public.apply_quest_reward(uuid, uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. close_day() — CREATE OR REPLACE : boss, titres, rédemption, malus (M4)
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

  v_new_consecutive := case when v_is_abuse_day then v_profile.consecutive_abuse_days + 1
                             else 0 end;

  v_penalty_multiplier := case
    when v_is_slump then 1.0
    when not v_is_abuse_day then 1.0
    when v_new_consecutive >= 3 then 2.0
    when v_new_consecutive = 2 then 1.5
    else 1.0
  end;

  -- Jour maudit (§3.6, M4) : pénalités doublées, cumulé avec l'escalade
  -- progressive (la SPEC ne borne que le multiplicateur d'XP positif à x3,
  -- pas les pénalités).
  select exists (
    select 1 from events_log
    where user_id = p_user_id and date = p_date and event_type = 'cursed'
  ) into v_cursed_active;
  if v_cursed_active then
    v_penalty_multiplier := v_penalty_multiplier * 2;
  end if;

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

  -- Quête de rédemption (§3.5, M4) : streak cassé sans bouclier disponible.
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

  -- Progression de la quête de rédemption active, si une existe.
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

  -- Titres de streak (§3.4) : déblocage idempotent à chaque palier atteint.
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

  -- Boss de la Procrastination (§3.7, M4).
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

        -- Récompense (§3.7) : +150 XP répartis également sur les 5 stats.
        declare
          v_stat  stat_type;
          v_share int := 30; -- 150 / 5 stats
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

  -- Timeout / deadline (§3.7) : 14 jours sans défaite = le boss dévore 10%
  -- de la stat la plus haute. Jamais de descente de niveau (SPEC §8) : seul
  -- current_xp est ponctionné, comme toute pénalité existante.
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

  -- Malus visible (§3.16) : état 3 = boss actif (priorité sur l'échelle
  -- 0-2 jours d'abus/parfaite, désormais atteignable depuis M4).
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
-- 6. Tirage quotidien (§3.6 événements, §3.14 quête secrète) — 08:00 local
-- ----------------------------------------------------------------------------
create function public.draw_daily_event(p_user_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    select * into v_habit from habits h
      where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
        and exists (
          select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
          where e::int = extract(isodow from p_date)::int
        )
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
        case v_habit.difficulty when 'easy' then 10 when 'medium' then 25 when 'hard' then 50 end)
    );
  elsif v_type = 'cursed' then
    perform public.enqueue_notification(
      p_user_id, 'event_cursed',
      jsonb_build_object('rank', (select rank from profiles where id = p_user_id))
    );
  end if;
end;
$$;

revoke execute on function public.draw_daily_event(uuid, date) from public, anon, authenticated;

-- Quête secrète (§3.14) : cible une habitude du jour, bonus caché jusqu'à
-- la complétion. « Fragment de coffre » omis : aucune mécanique de
-- fragments n'existe dans le schéma verrouillé, pas de sens à en inventer
-- une hors SPEC pour ce seul tirage.
create function public.draw_secret_quest(p_user_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_habit habits%rowtype;
  v_roll  numeric := random();
  v_reward jsonb;
begin
  if exists (
    select 1 from secret_quests where user_id = p_user_id and date = p_date
  ) then
    return;
  end if;

  select * into v_habit from habits h
    where h.user_id = p_user_id and h.active and h.created_at::date <= p_date
      and exists (
        select 1 from jsonb_array_elements_text(h.schedule -> 'days') e
        where e::int = extract(isodow from p_date)::int
      )
    order by random() limit 1;

  if v_habit.id is null then
    return;
  end if;

  if v_roll < 0.40 then
    v_reward := jsonb_build_object('type', 'xp_double');
  elsif v_roll < 0.75 then
    v_reward := jsonb_build_object('type', 'item', 'rarity', 'common');
  else
    v_reward := jsonb_build_object('type', 'shield');
  end if;

  insert into secret_quests (user_id, date, target_type, target_id, reward)
  values (p_user_id, p_date, 'habit', v_habit.id, v_reward);
end;
$$;

revoke execute on function public.draw_secret_quest(uuid, date) from public, anon, authenticated;

create function public.run_daily_tick()
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
    end if;
  end loop;
end;
$$;

revoke execute on function public.run_daily_tick() from public, anon, authenticated;

-- pg_cron déjà activée en M2 (create extension if not exists = idempotent).
create extension if not exists pg_cron;
select cron.schedule('daily-tick', '*/15 * * * *', $$select public.run_daily_tick();$$);

-- ----------------------------------------------------------------------------
-- 7. Quêtes hebdomadaires (§3.5) — génération lundi 00:00 local
-- ----------------------------------------------------------------------------
create function public.generate_weekly_quests(p_user_id uuid, p_week_start date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stat        stat_type;
  v_frequency   int;
  v_created     int := 0;
  v_reward_roll numeric;
begin
  -- Expire les quêtes hebdo de la semaine précédente encore actives.
  update quests
    set status = 'expired'
    where user_id = p_user_id and type = 'weekly' and status = 'active'
      and expires_at <= now();

  -- Déjà générées cette semaine ? (idempotence)
  if exists (
    select 1 from quests
    where user_id = p_user_id and type = 'weekly'
      and (definition ->> 'week_start')::date = p_week_start
  ) then
    return;
  end if;

  -- 2 quêtes sur 2 stats distinctes tirées au sort parmi celles ayant des
  -- habitudes actives (une stat sans habitude n'a pas de "fréquence
  -- habituelle" sur laquelle baser une cible).
  for v_stat in
    select unnest(enum_range(null::stat_type)) order by random()
  loop
    exit when v_created >= 2;

    select coalesce(sum(jsonb_array_length(schedule -> 'days')), 0) into v_frequency
      from habits
      where user_id = p_user_id and active and stat = v_stat;

    if v_frequency = 0 then
      continue;
    end if;

    v_reward_roll := random();

    insert into quests (user_id, type, definition, progress, target, reward, expires_at, status)
    values (
      p_user_id, 'weekly',
      jsonb_build_object('stat', v_stat, 'week_start', p_week_start),
      0, v_frequency + 1,
      case when v_reward_roll < 0.7
           then jsonb_build_object('type', 'xp_bonus', 'amount', 100, 'stat', v_stat)
           else jsonb_build_object('type', 'item', 'rarity', 'common')
      end,
      (p_week_start + 7)::timestamptz,
      'active'
    );

    v_created := v_created + 1;
  end loop;
end;
$$;

revoke execute on function public.generate_weekly_quests(uuid, date) from public, anon, authenticated;

create function public.run_weekly_tick()
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
  end loop;
end;
$$;

revoke execute on function public.run_weekly_tick() from public, anon, authenticated;

select cron.schedule('weekly-tick', '*/15 * * * *', $$select public.run_weekly_tick();$$);

-- ----------------------------------------------------------------------------
-- 8. complete_habit() — CREATE OR REPLACE : événements, quêtes, secret (M4)
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

  -- Heure de rush (§3.6, M4) : l'habitude tirée au sort vaut x2 avant midi.
  select payload ->> 'habit_id' into v_rush_habit_id
    from events_log
    where user_id = v_user_id and date = v_today and event_type = 'rush';

  if v_rush_habit_id is not null and v_rush_habit_id::uuid = p_habit_id
     and v_local_time < time '12:00' then
    v_multiplier := v_multiplier * 2;
  end if;

  -- Quête secrète (§3.14, M4) : révélée seulement à la complétion de la
  -- bonne habitude, jamais avant.
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

  -- Bonus journée parfaite (§3.2) : x1.5 sur la dernière habitude, x2 en
  -- plus si Potion d'Énergie active (M4) — cumulé, cap x3 (SPEC §3.2).
  select exists (
    select 1 from events_log
    where user_id = v_user_id and date = v_today and event_type = 'potion'
  ) into v_potion_active;

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
      v_multiplier := v_multiplier * (case when v_potion_active then 3.0 else 1.5 end);
    end if;
  end if;

  v_multiplier := least(3.0, v_multiplier);
  v_xp_earned := round(v_base_xp * v_multiplier);

  update streaks
    set current = v_new_current, best = v_new_best, last_completed_date = v_today
    where id = v_streak.id;

  insert into habit_logs (habit_id, user_id, date, completed_at, xp_earned, multiplier, is_express)
  values (p_habit_id, v_user_id, v_today, now(), v_xp_earned, v_multiplier, false);

  -- Coffre mystère (§3.6, M4) : condition = 3 habitudes complétées
  -- aujourd'hui. Récompense accordée une seule fois (events_log.resolved).
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

  -- Progression des quêtes hebdo actives correspondant à la stat (§3.5).
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
-- 9. File d'annonces événementielles — sélection + choix pondéré
-- ----------------------------------------------------------------------------
create function public.get_due_queued_notifications()
returns table (
  queue_id     uuid,
  user_id      uuid,
  habit_id     uuid,
  template_id  uuid,
  trigger_type text,
  body         text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      record;
  v_exclude  uuid[];
  v_template record;
begin
  for v_row in
    select nq.id, nq.user_id, nq.trigger_type, nq.vars, nq.habit_id
    from notification_queue nq
    where nq.sent_at is null
    order by nq.created_at
  loop
    select array_agg(t.tid) into v_exclude
      from (
        select nl.template_id as tid from notification_log nl
        where nl.user_id = v_row.user_id and nl.template_id is not null
        order by nl.sent_at desc limit 5
      ) t;

    select nt.id, nt.template into v_template
      from notification_templates nt
      where nt.active
        and nt.trigger_type = v_row.trigger_type
        and (v_exclude is null or nt.id <> all(v_exclude))
      order by -ln(random()) / nt.weight asc
      limit 1;

    if not found then
      continue;
    end if;

    queue_id := v_row.id;
    user_id := v_row.user_id;
    habit_id := v_row.habit_id;
    template_id := v_template.id;
    trigger_type := v_row.trigger_type;
    body := public.interpolate_template(v_template.template, v_row.vars);
    return next;
  end loop;
end;
$$;

revoke execute on function public.get_due_queued_notifications() from public, anon, authenticated;
grant execute on function public.get_due_queued_notifications() to service_role;

create function public.record_queue_notification_sent(p_queue_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update notification_queue set sent_at = now() where id = p_queue_id;
$$;

revoke execute on function public.record_queue_notification_sent(uuid) from public, anon, authenticated;
grant execute on function public.record_queue_notification_sent(uuid) to service_role;
