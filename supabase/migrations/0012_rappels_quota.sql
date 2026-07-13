-- ============================================================================
-- Rappels au RYTHME DU QUOTA
--
-- M8 a ouvert un trou : T-30/T-15 suppose une heure limite. Or une quête
-- hebdomadaire n'est en retard aucun mardi, et une quête journalière peut très
-- bien n'avoir aucune heure limite. Résultat : « 3 séances cette semaine »
-- pouvait se rater EN SILENCE.
--
-- Deux nouveaux déclencheurs comblent ça :
--
--   quota_day    — quota journalier SANS heure limite. Jusqu'à N rappels dans
--                  la journée, échelonnés (le dernier à 20 h). Au créneau i, on
--                  n'écrit que si le Chasseur en a fait MOINS DE i.
--
--   quota_period — quota hebdo/mensuel/annuel. Un rendez-vous quotidien à 19 h,
--                  mais on n'écrit QUE s'il est en retard sur le rythme. Au plus
--                  `quota` rappels par période.
--
-- Le principe, dans les deux cas : **dans les temps ⇒ silence**. Une notif qui
-- arrive alors qu'on est à jour n'est plus un rappel, c'est du bruit — et le
-- bruit, on finit par le couper.
--
-- (Les quêtes journalières AVEC heure limite gardent T-30/T-15 : ça marche et
--  c'est testé.)
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Choix du template — factorisé
--    La sélection (anti-répétition + filtres persona/ton + tirage pondéré)
--    était inline dans get_due_notifications. Trois boucles vont désormais en
--    avoir besoin : une seule définition.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.pick_notification_template(
  p_user_id  uuid,
  p_trigger  text,
  p_personas text[],
  p_tones    text[]
)
returns table (template_id uuid, template text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_exclude uuid[];
begin
  -- Anti-répétition : on écarte les 5 derniers templates envoyés à ce Chasseur.
  select array_agg(t.tid) into v_exclude
    from (
      select nl.template_id as tid
      from notification_log nl
      where nl.user_id = p_user_id and nl.template_id is not null
      order by nl.sent_at desc
      limit 5
    ) t;

  return query
    select nt.id, nt.template
    from notification_templates nt
    where nt.active
      and nt.trigger_type = p_trigger
      and (p_personas is null or nt.persona = any (p_personas))
      and (p_tones    is null or nt.tone    = any (p_tones))
      and (v_exclude  is null or nt.id     <> all (v_exclude))
    order by -ln(random()) / nt.weight asc
    limit 1;
end;
$$;

-- Créneaux d'un quota journalier : N rappels étalés, le dernier à 20 h — avant
-- le rituel du soir (21 h) et la clôture de minuit.
--   ×1 → 20h        ×2 → 15h, 20h        ×3 → 13h, 16h, 20h
create or replace function public.quota_day_slot_hour(p_frequency int, p_slot int)
returns int
language sql
immutable
set search_path = public
as $$
  select round(20 - (p_frequency - p_slot) * (11.0 / greatest(1, p_frequency)))::int;
$$;

revoke execute on function public.pick_notification_template(uuid, text, text[], text[])
  from public, anon, authenticated;
revoke execute on function public.quota_day_slot_hour(int, int)
  from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. La DÉCISION, séparée de l'horloge
--
--    « Faut-il écrire, maintenant, pour cette quête ? » est une règle de jeu.
--    La mêler à `now()` la rendait invérifiable : on ne peut pas attendre 13 h
--    pour lancer un test. Ces deux fonctions prennent l'instant LOCAL en
--    paramètre — get_due_notifications leur passe `now()`, les tests leur
--    passent ce qu'ils veulent.
-- ─────────────────────────────────────────────────────────────────────────────

-- Quel créneau de rappel s'ouvre à cet instant, pour ce quota journalier ?
-- NULL = aucun. Y compris : quota rempli, à jour sur le créneau, déjà rappelé.
create or replace function public.quota_day_due_slot(
  p_habit_id  uuid,
  p_local_now timestamp
)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_habit habits%rowtype;
  v_tz    text;
  v_today date := p_local_now::date;
  v_done  int;
  v_slot  int;
  v_sent  int;
  i       int;
begin
  select * into v_habit from habits where id = p_habit_id;

  if not found
     or not v_habit.active
     or v_habit.recurrence <> 'daily'
     or v_habit.deadline_time is not null   -- avec heure limite : T-30/T-15
     or v_habit.created_at::date > v_today
  then
    return null;
  end if;

  select timezone into v_tz from profiles where id = v_habit.user_id;

  select coalesce(hl.completions, 0) into v_done
    from habit_logs hl
    where hl.habit_id = p_habit_id and hl.date = v_today;
  v_done := coalesce(v_done, 0);

  -- Quota rempli : silence.
  if v_done >= v_habit.frequency then
    return null;
  end if;

  -- Un créneau vient-il de s'ouvrir ? Fenêtre de 5 min = cadence du cron.
  for i in 1..v_habit.frequency loop
    if extract(hour from p_local_now)::int = public.quota_day_slot_hour(v_habit.frequency, i)
       and extract(minute from p_local_now)::int < 5 then
      v_slot := i;
      exit;
    end if;
  end loop;

  if v_slot is null then
    return null;
  end if;

  -- ⭐ Au créneau i, il devrait en avoir fait i. À jour ⇒ ON SE TAIT.
  if v_done >= v_slot then
    return null;
  end if;

  -- Combien de rappels déjà partis aujourd'hui ? On COMPTE plutôt qu'on ne teste
  -- l'existence : ça rend l'envoi idempotent (cron rejoué) ET ça rattrape un
  -- créneau manqué sans jamais doubler.
  select count(*) into v_sent
    from notification_log nl
    join notification_templates nt on nt.id = nl.template_id
    where nl.habit_id = p_habit_id
      and (nl.sent_at at time zone v_tz)::date = v_today
      and nt.trigger_type = 'quota_day';

  if v_sent >= v_slot then
    return null;
  end if;

  return v_slot;
end;
$$;

-- Faut-il rappeler ce quota de période, maintenant ? Une seule raison d'écrire :
-- être EN RETARD SUR LE RYTHME.
create or replace function public.quota_period_is_due(
  p_habit_id  uuid,
  p_local_now timestamp
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_habit        habits%rowtype;
  v_tz           text;
  v_today        date := p_local_now::date;
  v_period_start date;
  v_period_end   date;
  v_done         int;
  v_expected     int;
  v_sent         int;
begin
  select * into v_habit from habits where id = p_habit_id;

  if not found
     or not v_habit.active
     or v_habit.recurrence not in ('weekly', 'monthly', 'yearly')
     or v_habit.created_at::date > v_today
  then
    return false;
  end if;

  -- Un seul rendez-vous par jour : 19 h.
  if extract(hour from p_local_now)::int <> 19
     or extract(minute from p_local_now)::int >= 5
  then
    return false;
  end if;

  select timezone into v_tz from profiles where id = v_habit.user_id;

  v_period_start := public.period_start(v_habit.recurrence, v_today);
  v_period_end   := public.period_end(v_habit.recurrence, v_today);
  v_done         := public.habit_period_completions(p_habit_id, v_today);

  -- Quota rempli : plus rien à dire jusqu'à la période suivante.
  if v_done >= v_habit.frequency then
    return false;
  end if;

  -- ⭐ LA condition. Attendu à ce stade = quota × (jours écoulés / durée).
  -- Celui qui a fait ses 3 séances dès le mardi n'entend jamais parler de rien.
  v_expected := ceil(
    v_habit.frequency::numeric
    * (v_today - v_period_start + 1)
    / (v_period_end - v_period_start + 1)
  )::int;

  if v_done >= v_expected then
    return false;
  end if;

  -- Un rappel par jour, pas plus.
  if exists (
    select 1 from notification_log nl
    join notification_templates nt on nt.id = nl.template_id
    where nl.habit_id = p_habit_id
      and (nl.sent_at at time zone v_tz)::date = v_today
      and nt.trigger_type = 'quota_period'
  ) then
    return false;
  end if;

  -- Plafond : jamais plus de rappels sur la période que le quota lui-même.
  -- « 3 séances par semaine » ⇒ 3 rappels au maximum.
  select count(*) into v_sent
    from notification_log nl
    join notification_templates nt on nt.id = nl.template_id
    where nl.habit_id = p_habit_id
      and (nl.sent_at at time zone v_tz)::date between v_period_start and v_period_end
      and nt.trigger_type = 'quota_period';

  return v_sent < v_habit.frequency;
end;
$$;

revoke execute on function public.quota_day_due_slot(uuid, timestamp)   from public, anon, authenticated;
revoke execute on function public.quota_period_is_due(uuid, timestamp)  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. get_due_notifications — trois boucles au lieu d'une
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.get_due_notifications()
returns table(user_id uuid, habit_id uuid, template_id uuid, trigger_type text, body text)
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
  v_template         record;
  v_base_xp          int;
  v_habit_streak     int;
  v_vars             jsonb;
  v_done             int;
  v_slot             int;
  v_sent             int;
  v_period_start     date;
  v_period_end       date;
  v_expected         int;
  v_days_left        int;
  i                  int;
begin
  -- ═══ A. Quêtes journalières AVEC heure limite → T-30 / T-15 (inchangé) ═══
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

    select * into v_template
      from public.pick_notification_template(
        v_row.user_id, v_trigger, v_persona_filter, v_tone_filter);
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
    template_id := v_template.template_id;
    trigger_type := v_trigger;
    body := public.interpolate_template(v_template.template, v_vars);
    return next;
  end loop;

  -- ═══ B. Quotas JOURNALIERS sans heure limite → créneaux échelonnés ═══
  for v_row in
    select h.id as habit_id, h.user_id, h.name, h.stat, h.difficulty,
           h.frequency, p.timezone
    from habits h
    join profiles p on p.id = h.user_id
    where h.active
      and h.recurrence = 'daily'
      and h.deadline_time is null        -- avec heure limite, c'est T-30/T-15
  loop
    v_local_now := now() at time zone v_row.timezone;
    v_local_today := v_local_now::date;

    if not exists (
      select 1 from habits h2
      where h2.id = v_row.habit_id and h2.created_at::date <= v_local_today
    ) then
      continue;
    end if;

    v_slot := public.quota_day_due_slot(v_row.habit_id, v_local_now);
    if v_slot is null then
      continue;                    -- rien à dire : rempli, à jour, ou déjà rappelé
    end if;

    select coalesce(hl.completions, 0) into v_done
      from habit_logs hl
      where hl.habit_id = v_row.habit_id and hl.date = v_local_today;
    v_done := coalesce(v_done, 0);

    v_ctx := public.get_notification_context(v_row.user_id);

    -- Escalade dans la journée : on commence en mentor, on finit en Boss.
    if (v_ctx ->> 'is_slump')::boolean then
      v_persona_filter := null;
      v_tone_filter := array['supportive'];   -- §3.9 : on ne frappe pas quelqu'un à terre
    elsif v_slot = v_row.frequency then
      v_persona_filter := array['boss'];      -- dernière fenêtre avant minuit
      v_tone_filter := null;
    elsif v_slot = 1 then
      v_persona_filter := array['mentor'];
      v_tone_filter := null;
    else
      v_persona_filter := array['system'];
      v_tone_filter := null;
    end if;

    select * into v_template
      from public.pick_notification_template(
        v_row.user_id, 'quota_day', v_persona_filter, v_tone_filter);
    if not found then
      continue;
    end if;

    v_base_xp := public.base_xp(v_row.difficulty);

    v_vars := jsonb_build_object(
      'habit', v_row.name,
      'xp', v_base_xp,
      'penalty', round(v_base_xp * 0.4 * (v_row.frequency - v_done)),
      'stat', v_row.stat,
      'quota', v_row.frequency,
      'done', v_done,
      'remaining', v_row.frequency - v_done,
      'rank', (select p2.rank from profiles p2 where p2.id = v_row.user_id),
      'streak', coalesce((select s.current from streaks s
                          where s.user_id = v_row.user_id
                            and s.habit_id = v_row.habit_id), 0)
    );

    user_id := v_row.user_id;
    habit_id := v_row.habit_id;
    template_id := v_template.template_id;
    trigger_type := 'quota_day';
    body := public.interpolate_template(v_template.template, v_vars);
    return next;
  end loop;

  -- ═══ C. Quotas HEBDO / MENSUEL / ANNUEL → seulement si en retard ═══
  for v_row in
    select h.id as habit_id, h.user_id, h.name, h.stat, h.difficulty,
           h.recurrence, h.frequency, p.timezone
    from habits h
    join profiles p on p.id = h.user_id
    where h.active
      and h.recurrence in ('weekly', 'monthly', 'yearly')
  loop
    v_local_now := now() at time zone v_row.timezone;
    v_local_today := v_local_now::date;

    if not public.quota_period_is_due(v_row.habit_id, v_local_now) then
      continue;                    -- dans les temps, ou déjà rappelé aujourd'hui
    end if;

    v_period_start := public.period_start(v_row.recurrence, v_local_today);
    v_period_end   := public.period_end(v_row.recurrence, v_local_today);
    v_done         := public.habit_period_completions(v_row.habit_id, v_local_today);

    v_ctx := public.get_notification_context(v_row.user_id);
    v_days_left := v_period_end - v_local_today;

    -- Le ton se durcit à mesure que la clôture approche.
    if (v_ctx ->> 'is_slump')::boolean then
      v_persona_filter := null;
      v_tone_filter := array['supportive'];
    elsif v_days_left <= 1 then
      v_persona_filter := array['boss'];
      v_tone_filter := null;
    elsif v_days_left <= 2 then
      v_persona_filter := array['system'];
      v_tone_filter := null;
    else
      v_persona_filter := array['mentor'];
      v_tone_filter := null;
    end if;

    select * into v_template
      from public.pick_notification_template(
        v_row.user_id, 'quota_period', v_persona_filter, v_tone_filter);
    if not found then
      continue;
    end if;

    v_base_xp := public.base_xp(v_row.difficulty);

    v_vars := jsonb_build_object(
      'habit', v_row.name,
      'xp', v_base_xp,
      -- La pénalité annoncée est celle qui tombera VRAIMENT à la clôture :
      -- 40 % de l'XP × le manquant (cf. close_day).
      'penalty', round(v_base_xp * 0.4 * (v_row.frequency - v_done)),
      'stat', v_row.stat,
      'quota', v_row.frequency,
      'done', v_done,
      'remaining', v_row.frequency - v_done,
      'days_left', v_days_left,
      'period', case v_row.recurrence
                  when 'weekly'  then 'cette semaine'
                  when 'monthly' then 'ce mois-ci'
                  when 'yearly'  then 'cette année'
                end,
      'rank', (select p2.rank from profiles p2 where p2.id = v_row.user_id),
      'streak', coalesce((select s.current from streaks s
                          where s.user_id = v_row.user_id
                            and s.habit_id = v_row.habit_id), 0)
    );

    user_id := v_row.user_id;
    habit_id := v_row.habit_id;
    template_id := v_template.template_id;
    trigger_type := 'quota_period';
    body := public.interpolate_template(v_template.template, v_vars);
    return next;
  end loop;
end;
$$;

revoke execute on function public.get_due_notifications() from public, anon, authenticated;
