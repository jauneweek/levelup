-- ============================================================================
-- LEVELUP — Migration 0004 : moteur de notifications (M3)
-- Réf : SPEC §4.1 (architecture), §4.2 (templates), §4.3 (contexte),
-- §4.4 (règles d'escalade).
--
-- Portée M3 (roadmap) : uniquement les rappels T-30/T-15 par habitude et
-- leur escalade. Les autres triggers du seed (perfect_day, level_up,
-- rank_up, boss_*, streak_milestone, morning_brief...) sont événementiels
-- et seront câblés avec leurs mécaniques respectives (M4+), pas ici.
--
-- Architecture : toute la logique (sélection, escalade, choix pondéré du
-- template, interpolation) vit en SQL — testée via pgTAP. L'Edge Function
-- `send-notifications` (Deno) n'est qu'un dispatcher fin : appelle
-- get_due_notifications(), envoie via web-push, log via
-- record_notification_sent(). Ni l'une ni l'autre ne sont exposées au
-- client (REVOKE EXECUTE FROM PUBLIC + grant service_role only).
--
-- Contenu :
--   0. Grants service_role — jamais nécessaires avant M3 (M0 n'accordait
--      les privilèges de base qu'à `authenticated`). service_role a
--      bypassrls mais ça ne dispense pas des GRANT de table de base :
--      l'Edge Function en avait besoin pour lire push_subscriptions.
--   1. completion_rate_7d(user_id, date) — helper réutilisable.
--   2. get_notification_context(user_id) — §4.3.
--   3. interpolate_template(template, vars) — {var} -> valeur.
--   4. get_due_notifications() — sélection + escalade + choix pondéré.
--   5. record_notification_sent(user_id, template_id, habit_id).
--
-- Correction héritée de M0 : notification_log était en écriture libre
-- pour le client (policy "for all" générique, même trou que user_stats
-- avant sa correction en M1). Un client pourrait manipuler l'historique
-- qui alimente l'anti-répétition et l'escalade (§4.4). Passé en lecture
-- seule ; écriture uniquement via record_notification_sent().
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Grants service_role (backend de confiance : accès large légitime)
-- ----------------------------------------------------------------------------
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant all on sequences to service_role;

-- notification_log : durcissement anti-triche (même correction que M1 pour
-- user_stats/habit_logs/streaks).
drop policy notification_log_owner on notification_log;
create policy notification_log_read on notification_log
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on notification_log from authenticated;

-- ----------------------------------------------------------------------------
-- 1. Taux de complétion glissant 7 jours (habitudes uniquement — todos M5)
-- ----------------------------------------------------------------------------
create function public.completion_rate_7d(p_user_id uuid, p_date date)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(
    sum(completed_count)::numeric / nullif(sum(scheduled_count), 0), 1.0
  )
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
$$;

revoke execute on function public.completion_rate_7d(uuid, date) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Contexte utilisateur (SPEC §4.3)
-- ----------------------------------------------------------------------------
create function public.get_notification_context(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz          text;
  v_today       date;
  v_yesterday   date;
  v_rate_7d     numeric;
  v_has_history boolean;
  v_ignored     int;
  v_streak      int;
  v_boss_active boolean;
begin
  select timezone into v_tz from profiles where id = p_user_id;
  v_today := (now() at time zone v_tz)::date;
  v_yesterday := v_today - 1;

  -- Taux calculé sur les jours pleinement écoulés (hier et avant) : la
  -- journée en cours n'est pas terminée, une habitude pas encore cochée
  -- aujourd'hui ne doit pas compter comme un échec avant même minuit.
  v_rate_7d := public.completion_rate_7d(p_user_id, v_yesterday);

  -- Un compte neuf (aucune habitude ayant vécu au moins un jour plein) n'a
  -- pas d'historique à juger : ni slump, ni régulier, ton neutre par défaut
  -- (trouvé en testant M3 en conditions réelles — un compte tout juste créé
  -- se retrouvait classé "slump" par défaut, ce qui écrasait l'escalade).
  select exists (
    select 1 from habits h
    where h.user_id = p_user_id and h.created_at::date <= v_yesterday
  ) into v_has_history;

  select count(distinct nl.habit_id) into v_ignored
    from notification_log nl
    where nl.user_id = p_user_id
      and nl.sent_at::date = v_today
      and nl.habit_id is not null
      and not exists (
        select 1 from habit_logs hl
        where hl.habit_id = nl.habit_id and hl.date = v_today and hl.completed_at is not null
      );

  select current into v_streak from streaks
    where user_id = p_user_id and habit_id is null;

  select exists (
    select 1 from boss_fights where user_id = p_user_id and status = 'active'
  ) into v_boss_active;

  return jsonb_build_object(
    'completion_rate_7d', v_rate_7d,
    'is_slump', v_has_history and v_rate_7d < 0.40,
    'is_regular', v_has_history and v_rate_7d > 0.85,
    'ignored_count_today', v_ignored,
    'current_streak', coalesce(v_streak, 0),
    'boss_active', v_boss_active
  );
end;
$$;

revoke execute on function public.get_notification_context(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Interpolation de template : remplace {var} par sa valeur
-- ----------------------------------------------------------------------------
create function public.interpolate_template(p_template text, p_vars jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_result text := p_template;
  v_key    text;
  v_value  text;
begin
  for v_key, v_value in select key, value from jsonb_each_text(p_vars)
  loop
    v_result := replace(v_result, '{' || v_key || '}', coalesce(v_value, ''));
  end loop;
  return v_result;
end;
$$;

revoke execute on function public.interpolate_template(text, jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. get_due_notifications — sélection T-30/T-15 + escalade + choix pondéré
--
-- Fenêtres alignées sur le cron */5min (SPEC §4.1) : T-30 = [26,30] min
-- restantes, T-15 = [11,15] min restantes. Idempotent par construction :
-- ignore une habitude si son trigger du jour a déjà été loggé.
-- ----------------------------------------------------------------------------
create function public.get_due_notifications()
returns table (
  user_id       uuid,
  habit_id      uuid,
  template_id   uuid,
  trigger_type  text,
  body          text
)
language plpgsql
security definer
set search_path = public
as $$
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
  for v_row in
    select h.id as habit_id, h.user_id, h.name, h.stat, h.difficulty,
           h.deadline_time, p.timezone
    from habits h
    join profiles p on p.id = h.user_id
    where h.active and h.deadline_time is not null
  loop
    v_local_now := now() at time zone v_row.timezone;
    v_local_today := v_local_now::date;

    -- Habitude programmée aujourd'hui et créée avant aujourd'hui ?
    if not exists (
      select 1 from habits h2
      where h2.id = v_row.habit_id
        and h2.created_at::date <= v_local_today
        and exists (
          select 1 from jsonb_array_elements_text(h2.schedule -> 'days') e
          where e::int = extract(isodow from v_local_today)::int
        )
    ) then
      continue;
    end if;

    -- Déjà complétée aujourd'hui ? Plus besoin de la rappeler.
    if exists (
      select 1 from habit_logs hl
      where hl.habit_id = v_row.habit_id and hl.date = v_local_today
        and hl.completed_at is not null
    ) then
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

    -- Idempotence : ce trigger a-t-il déjà été envoyé pour cette habitude
    -- aujourd'hui (double-tick de cron, redéploiement, etc.) ?
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

    -- Utilisateur régulier (7j > 85%) : fréquence réduite, T-15 seulement.
    if (v_ctx ->> 'is_regular')::boolean and v_trigger = 't30' then
      continue;
    end if;

    -- Règles d'escalade (SPEC §4.4).
    v_ignored_t30_here := exists (
      select 1 from notification_log nl
      join notification_templates nt on nt.id = nl.template_id
      where nl.habit_id = v_row.habit_id
        and nl.sent_at::date = v_local_today
        and nt.trigger_type = 't30'
    );

    if (v_ctx ->> 'is_slump')::boolean then
      -- Mode slump : uniquement supportive, jamais le Boss.
      v_persona_filter := null;
      v_tone_filter := array['supportive'];
    elsif v_trigger = 't15' and v_ignored_t30_here then
      v_persona_filter := array['system'];
      v_tone_filter := null;
    elsif v_trigger = 't15' and (v_ctx ->> 'ignored_count_today')::int >= 2 then
      v_persona_filter := array['boss'];
      v_tone_filter := null;
    else
      v_persona_filter := null;
      v_tone_filter := null;
    end if;

    -- Anti-répétition : exclure les 5 derniers templates envoyés au user.
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
      -- Filtrage trop strict (rare) : on ne bloque pas le batch pour autant.
      continue;
    end if;

    v_base_xp := case v_row.difficulty
      when 'easy' then 10 when 'medium' then 25 when 'hard' then 50
    end;

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
$$;

revoke execute on function public.get_due_notifications() from public, anon, authenticated;
grant execute on function public.get_due_notifications() to service_role;

-- ----------------------------------------------------------------------------
-- 5. record_notification_sent — log après tentative d'envoi (Edge Function)
-- ----------------------------------------------------------------------------
create function public.record_notification_sent(
  p_user_id uuid, p_template_id uuid, p_habit_id uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notification_log (user_id, template_id, habit_id)
  values (p_user_id, p_template_id, p_habit_id);
$$;

revoke execute on function public.record_notification_sent(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.record_notification_sent(uuid, uuid, uuid) to service_role;
