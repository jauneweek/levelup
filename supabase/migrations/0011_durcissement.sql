-- ============================================================================
-- Durcissement — remontées du linter Supabase après 0008/0010.
-- ============================================================================

-- 1. `search_path` figé sur les fonctions pures introduites par M8 et l'Économie.
--
--    Elles sont SECURITY INVOKER et ne touchent aucune table, donc le risque
--    réel est nul — mais toutes les autres fonctions du projet figent leur
--    search_path, et une exception non justifiée finit toujours par devenir une
--    règle. Contrepartie assumée : une fonction SQL avec `SET` n'est plus
--    « inlinée » par le planificateur. Sur une poignée d'habitudes par
--    utilisateur, c'est invisible.
alter function public.base_xp(difficulty)                    set search_path = public;
alter function public.period_days(recurrence_type)           set search_path = public;
alter function public.period_start(recurrence_type, date)    set search_path = public;
alter function public.period_end(recurrence_type, date)      set search_path = public;
alter function public.hunter_xp_to_next(int)                 set search_path = public;
alter function public.hunter_level_in_rank(int)              set search_path = public;

-- 2. `current_user_in_guild` était exécutable par `anon`.
--
--    Sans session, `auth.uid()` est nul et la fonction renvoie faux : aucune
--    fuite. Mais c'est une fonction SECURITY DEFINER exposée sur l'API REST
--    publique, et il n'y a aucune raison qu'un visiteur non connecté puisse
--    l'appeler. (Elle sert de garde aux policies RLS des guildes — hors scope
--    V1, mais autant fermer la porte tout de suite.)
revoke execute on function public.current_user_in_guild(uuid) from anon;

-- 3. `hunter_xp_to_next` : la plateforme Supabase accorde EXECUTE à anon par
--    défaut sur toute fonction neuve. Elle sert à afficher la barre d'XP côté
--    client connecté, pas aux visiteurs.
revoke execute on function public.hunter_xp_to_next(int) from anon;
