-- =============================================================
-- LEVELUP — Templates de rappel au RYTHME DU QUOTA
-- Fichier : supabase/seed/quota_notifications_seed.sql
--
-- Complète le seed principal. Deux nouveaux déclencheurs, pour les quêtes que
-- T-30/T-15 ne savait pas rappeler :
--
--   quota_day    — quota JOURNALIER sans heure limite. Jusqu'à N rappels dans
--                  la journée, échelonnés. Au créneau i, on n'écrit que si le
--                  Chasseur en a fait MOINS DE i. Dans les temps ⇒ silence.
--
--   quota_period — quota hebdo / mensuel / annuel. Au plus N rappels par
--                  période, un par jour maximum, et uniquement les jours où il
--                  est EN RETARD SUR LE RYTHME. Le ton se durcit à mesure que
--                  la clôture approche.
--
-- Variables : {habit} {remaining} {quota} {done} {xp} {penalty} {stat}
--             {rank} {streak} {days_left} {period}
--   {remaining} = combien il en reste à faire dans la période
--   {days_left} = jours restants avant la clôture (quota_period)
--   {period}    = « cette semaine » / « ce mois-ci » / « cette année »
-- =============================================================

INSERT INTO notification_templates (persona, tone, trigger_type, template, weight, active) VALUES

-- =========================================================
-- quota_day — le quota du jour n'est pas rempli
-- =========================================================
('mentor', 'neutral', 'quota_day',
 'Il te reste {remaining} × « {habit} » aujourd''hui. +{xp} XP {stat} à chaque fois.', 10, true),
('mentor', 'neutral', 'quota_day',
 '{habit} : {done} sur {quota}. La journée n''est pas finie.', 10, true),
('mentor', 'neutral', 'quota_day',
 'Encore {remaining} × « {habit} » et ton quota du jour est plein.', 8, true),

('mentor', 'supportive', 'quota_day',
 'Pas encore fait « {habit} » ? Il en reste {remaining}. Une seule suffit à relancer la machine.', 10, true),
('mentor', 'supportive', 'quota_day',
 '{habit}, {remaining} restantes. Commence par une. Le reste suivra tout seul.', 10, true),

('system', 'neutral', 'quota_day',
 '[SYSTÈME] Quota du jour : « {habit} » — {done}/{quota}. Récompense : +{xp} XP {stat}.', 10, true),
('system', 'neutral', 'quota_day',
 '[SYSTÈME] Objectif « {habit} » incomplet. Reste à valider : {remaining}. Échec à minuit : -{penalty} XP.', 10, true),
('system', 'neutral', 'quota_day',
 '[SYSTÈME] Chasseur de rang {rank}. Quête « {habit} » : {remaining} en attente. Fenêtre : jusqu''à minuit.', 8, true),

('boss', 'harsh', 'quota_day',
 'Tu as promis {quota} × « {habit} ». Il en manque {remaining}. Les promesses ne comptent pas, les actes si.', 10, true),
('boss', 'harsh', 'quota_day',
 'Dernière fenêtre pour « {habit} ». {remaining} à faire, et minuit ne négocie pas.', 10, true),
('boss', 'harsh', 'quota_day',
 'Un Chasseur de rang {rank} laisse traîner {remaining} × « {habit} » ? Le Système note tout.', 8, true),

-- =========================================================
-- quota_period — en retard sur le rythme de la période
-- =========================================================
('mentor', 'neutral', 'quota_period',
 '« {habit} » : {done} sur {quota} {period}. Il te reste {days_left} jours.', 10, true),
('mentor', 'neutral', 'quota_period',
 'Il te manque {remaining} × « {habit} » {period}. +{xp} XP {stat} à chaque fois.', 10, true),

('mentor', 'supportive', 'quota_period',
 '{remaining} × « {habit} » en {days_left} jours. Largement jouable. Une aujourd''hui et c''est presque plié.', 10, true),
('mentor', 'supportive', 'quota_period',
 'Tu as pris du retard sur « {habit} », rien de grave : {remaining} à caser en {days_left} jours.', 10, true),

('system', 'neutral', 'quota_period',
 '[SYSTÈME] Quota {period} : « {habit} » — {done}/{quota}. Fenêtre restante : {days_left} jours.', 10, true),
('system', 'neutral', 'quota_period',
 '[SYSTÈME] Période en cours de clôture. « {habit} » : {remaining} manquant(s). Pénalité à la clôture : -{penalty} XP.', 10, true),

('boss', 'harsh', 'quota_period',
 '{days_left} jours. {remaining} × « {habit} ». Les comptes se règlent à la clôture.', 10, true),
('boss', 'harsh', 'quota_period',
 'Tu t''es engagé sur {quota} × « {habit} » {period}. Il en reste {remaining} et {days_left} jours. Fais le calcul.', 10, true);
