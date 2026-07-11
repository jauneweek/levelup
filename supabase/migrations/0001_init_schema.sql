-- ============================================================================
-- LEVELUP — Migration 0001 : schéma initial
-- Réf : SPEC §5 (modèle de données), §8 (idempotence des crons), §9 (n/a).
--
-- Contenu :
--   1. Extensions
--   2. Enums de jeu
--   3. Tables (24) — profiles porte timezone + emblem_damage
--   4. Contraintes uniques d'idempotence (crons rejouables)
--   5. RLS activé partout + policies (owner-only, catalogue, guilde)
--   6. Grants rôles Supabase
--   7. Trigger handle_new_user : profil + 5 stats + streak global
--
-- Règle : toute la logique de jeu vit côté serveur (fonctions à venir M1+).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto; -- gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 2. ENUMS DE JEU
--    persona / tone / trigger_type des notifications restent en TEXT
--    (le moteur §4 évolue ; ~20 triggers dans le seed → pas d'enum figé).
-- ----------------------------------------------------------------------------
create type hunter_rank as enum ('E', 'D', 'C', 'B', 'A', 'S');
create type stat_type as enum ('FOR', 'INT', 'SAG', 'PRO', 'END');
create type difficulty as enum ('easy', 'medium', 'hard');
create type quest_type as enum ('weekly', 'redemption');
create type item_type as enum ('potion', 'shield', 'skin', 'badge');
create type shadow_grade as enum ('soldat', 'chevalier', 'general', 'marechal');
create type secret_target_type as enum ('habit', 'todo');

-- ----------------------------------------------------------------------------
-- 3. TABLES
-- ----------------------------------------------------------------------------

-- Profil (1-1 avec auth.users). timezone = pivot de tous les crons (SPEC §8).
create table profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  username      text unique,
  rank          hunter_rank not null default 'E',
  global_level  int not null default 1,
  timezone      text not null default 'UTC',
  emblem_damage int not null default 0 check (emblem_damage between 0 and 3), -- §3.16
  created_at    timestamptz not null default now()
);

-- 5 statistiques par joueur.
create table user_stats (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  stat       stat_type not null,
  level      int not null default 1,
  current_xp int not null default 0 check (current_xp >= 0),
  unique (user_id, stat)
);

-- Habitudes récurrentes.
create table habits (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles (id) on delete cascade,
  name            text not null,
  stat            stat_type not null,
  difficulty      difficulty not null,
  schedule        jsonb not null default '{"days":[1,2,3,4,5,6,7]}'::jsonb,
  deadline_time   time,
  minimal_version text,                    -- §3.10 donjon express
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);

-- Journal de complétion. UNIQUE(habit_id,date) = idempotence (§8).
create table habit_logs (
  id           uuid primary key default gen_random_uuid(),
  habit_id     uuid not null references habits (id) on delete cascade,
  user_id      uuid not null references profiles (id) on delete cascade,
  date         date not null,
  completed_at timestamptz,
  xp_earned    int not null default 0,
  multiplier   numeric(4, 2) not null default 1.0,
  is_express   boolean not null default false, -- §3.10
  unique (habit_id, date)
);

-- Streaks. habit_id NULL = streak global.
create table streaks (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references profiles (id) on delete cascade,
  habit_id            uuid references habits (id) on delete cascade,
  current             int not null default 0,
  best                int not null default 0,
  shields             int not null default 0 check (shields between 0 and 3), -- §3.4
  last_completed_date date
);

-- Quêtes hebdo / rédemption.
create table quests (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  type       quest_type not null,
  definition jsonb not null default '{}'::jsonb,
  progress   int not null default 0,
  target     int not null default 1,
  reward     jsonb not null default '{}'::jsonb,
  expires_at timestamptz,
  status     text not null default 'active',
  created_at timestamptz not null default now()
);

-- Catalogue d'items.
create table items (
  id     uuid primary key default gen_random_uuid(),
  name   text not null,
  type   item_type not null,
  rarity text not null default 'common',
  icon   text,
  effect jsonb not null default '{}'::jsonb
);

-- Inventaire.
create table user_items (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references profiles (id) on delete cascade,
  item_id  uuid not null references items (id) on delete cascade,
  quantity int not null default 1 check (quantity >= 0),
  equipped boolean not null default false,
  unique (user_id, item_id)
);

-- Catalogue de titres.
create table titles (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  condition jsonb not null default '{}'::jsonb
);

-- Titres débloqués.
create table user_titles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles (id) on delete cascade,
  title_id    uuid not null references titles (id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  equipped    boolean not null default false,
  unique (user_id, title_id)
);

-- Boss de la Procrastination (§3.7).
create table boss_fights (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  boss_type  text not null default 'procrastination',
  hp         int not null,
  max_hp     int not null default 3,
  spawned_at timestamptz not null default now(),
  status     text not null default 'active'
);

-- Événements aléatoires (§3.6). UNIQUE(user,type,jour) = idempotence tirage.
create table events_log (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  event_type text not null,
  date       date not null,
  payload    jsonb not null default '{}'::jsonb,
  resolved   boolean not null default false,
  unique (user_id, event_type, date)
);

-- Souscriptions Web Push (M3).
create table push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  endpoint   text not null,
  keys       jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);

-- Banque de templates (catalogue partagé). Colonnes = seed §4.2.
create table notification_templates (
  id           uuid primary key default gen_random_uuid(),
  persona      text not null,
  tone         text not null,
  trigger_type text not null,
  template     text not null,
  weight       int not null default 10,
  active       boolean not null default true
);

-- Journal des notifications envoyées (anti-répétition §4.4).
create table notification_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles (id) on delete cascade,
  template_id uuid references notification_templates (id) on delete set null,
  habit_id    uuid references habits (id) on delete set null,
  sent_at     timestamptz not null default now(),
  clicked     boolean not null default false
);

-- To-dos ponctuelles (§3.8). date = jour d'exécution.
create table todos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles (id) on delete cascade,
  title         text not null,
  stat          stat_type not null default 'PRO',
  difficulty    difficulty not null default 'easy',
  date          date not null,
  deadline_time time,
  completed_at  timestamptz,
  xp_earned     int not null default 0,
  created_at    timestamptz not null default now()
);

-- Snapshots quotidiens (§3.12 Fantôme). UNIQUE(user,jour) = idempotence.
create table daily_snapshots (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references profiles (id) on delete cascade,
  date               date not null,
  global_level       int not null,
  stats              jsonb not null default '{}'::jsonb,
  streak             int not null default 0,
  completion_rate_7d numeric(5, 2) not null default 0,
  unique (user_id, date)
);

-- Armée des Ombres (§3.11).
create table shadows (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references profiles (id) on delete cascade,
  habit_id                  uuid references habits (id) on delete set null,
  name                      text not null,
  grade                     shadow_grade not null default 'soldat',
  asset_id                  text,
  extracted_at              timestamptz not null default now(),
  completions_at_extraction int not null
);

-- Guildes (§3.13, V1 = 2 membres max, architecture prête).
create table guilds (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

create table guild_members (
  id        uuid primary key default gen_random_uuid(),
  guild_id  uuid not null references guilds (id) on delete cascade,
  user_id   uuid not null references profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (guild_id, user_id)
);

create table raid_fights (
  id         uuid primary key default gen_random_uuid(),
  guild_id   uuid not null references guilds (id) on delete cascade,
  week_start date not null,
  hp         int not null,
  max_hp     int not null default 5,
  status     text not null default 'active',
  unique (guild_id, week_start)
);

-- Journal du Chasseur (§3.15). UNIQUE(user,semaine).
create table journal_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles (id) on delete cascade,
  week_start date not null,
  payload    jsonb not null default '{}'::jsonb,
  image_url  text,
  created_at timestamptz not null default now(),
  unique (user_id, week_start)
);

-- Quête secrète quotidienne (§3.14). UNIQUE(user,jour) = idempotence.
create table secret_quests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles (id) on delete cascade,
  date        date not null,
  target_type secret_target_type not null,
  target_id   uuid,
  reward      jsonb not null default '{}'::jsonb,
  revealed    boolean not null default false,
  unique (user_id, date)
);

-- ----------------------------------------------------------------------------
-- 4. INDEX (idempotence streak global + accès fréquents)
-- ----------------------------------------------------------------------------
-- Streak global (habit_id NULL) : une seule ligne par user.
create unique index streaks_global_uidx on streaks (user_id) where habit_id is null;
-- Streak par habitude : une ligne par (user, habit).
create unique index streaks_habit_uidx on streaks (user_id, habit_id) where habit_id is not null;

create index habit_logs_user_date_idx on habit_logs (user_id, date);
create index habits_user_idx on habits (user_id);
create index todos_user_date_idx on todos (user_id, date);
create index notification_log_user_sent_idx on notification_log (user_id, sent_at desc);

-- ----------------------------------------------------------------------------
-- 5. RLS + POLICIES
-- ----------------------------------------------------------------------------

-- Helper anti-récursion pour les policies de guilde (SECURITY DEFINER =
-- bypass RLS sur guild_members, évite la récursion infinie).
create function public.current_user_in_guild(g uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.guild_members
    where guild_id = g and user_id = auth.uid()
  );
$$;

-- Active RLS sur toutes les tables du schéma public.
do $$
declare t text;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security;', t);
  end loop;
end $$;

-- --- Tables owner-only : accès total au propriétaire (user_id = auth.uid()) ---
do $$
declare t text;
begin
  foreach t in array array[
    'user_stats', 'habits', 'habit_logs', 'streaks', 'quests',
    'user_items', 'user_titles', 'boss_fights', 'events_log',
    'push_subscriptions', 'notification_log', 'todos',
    'daily_snapshots', 'shadows', 'journal_entries', 'secret_quests'
  ]
  loop
    execute format(
      'create policy %1$I_owner on public.%1$I for all to authenticated '
      || 'using (user_id = auth.uid()) with check (user_id = auth.uid());', t
    );
  end loop;
end $$;

-- --- profiles : le propriétaire voit/édite sa ligne (id = auth.uid()) ---
create policy profiles_owner on public.profiles
  for all to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- --- Catalogues : lecture seule pour authentifiés, écriture = service role ---
create policy notification_templates_read on public.notification_templates
  for select to authenticated using (true);
create policy items_read on public.items
  for select to authenticated using (true);
create policy titles_read on public.titles
  for select to authenticated using (true);

-- --- Guilde : accès basé sur l'appartenance ---
create policy guilds_member_read on public.guilds
  for select to authenticated using (public.current_user_in_guild(id));
create policy guilds_create on public.guilds
  for insert to authenticated with check (true);
create policy guilds_member_update on public.guilds
  for update to authenticated using (public.current_user_in_guild(id));

create policy guild_members_read on public.guild_members
  for select to authenticated using (public.current_user_in_guild(guild_id));
create policy guild_members_join on public.guild_members
  for insert to authenticated with check (user_id = auth.uid());
create policy guild_members_leave on public.guild_members
  for delete to authenticated using (user_id = auth.uid());

create policy raid_fights_member_read on public.raid_fights
  for select to authenticated using (public.current_user_in_guild(guild_id));

-- ----------------------------------------------------------------------------
-- 6. GRANTS (RLS reste la vraie barrière ; les grants ouvrent l'accès table)
-- ----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- ----------------------------------------------------------------------------
-- 7. TRIGGER : création du profil + 5 stats + streak global à l'inscription
-- ----------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  tz text := coalesce(new.raw_user_meta_data ->> 'timezone', 'UTC');
begin
  insert into public.profiles (id, timezone) values (new.id, tz);

  insert into public.user_stats (user_id, stat)
  select new.id, s
  from unnest(enum_range(null::stat_type)) as s;

  insert into public.streaks (user_id, habit_id) values (new.id, null);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Fonction trigger : jamais un endpoint client (appelée seulement par
-- le trigger ci-dessus). Postgres accorde EXECUTE à PUBLIC par défaut.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
