-- =============================================================
-- LEVELUP — Seed des templates de notifications
-- Fichier : supabase/seed/notification_templates.sql
-- Personas : mentor | system | boss | streak
-- Tones    : neutral | supportive | harsh | hype
-- Triggers : t30 | t15 | event_potion | event_chest | event_rush |
--            event_cursed | boss_spawn | boss_damage | boss_heal |
--            boss_defeat | boss_deadline | streak_milestone |
--            streak_progress | streak_shield | redemption |
--            perfect_day | rank_up | level_up | penalty | morning_brief
-- Variables : {habit} {xp} {penalty} {minutes_left} {streak} {stat}
--             {title_next} {days_to_title} {boss_hp} {level} {rank}
--             {item} {shields}
-- =============================================================

INSERT INTO notification_templates (persona, tone, trigger_type, template, weight, active) VALUES

-- =========================================================
-- T-30 — Premier rappel (ton normal)
-- =========================================================
('mentor', 'neutral', 't30', 'Il te reste {minutes_left} min pour {habit}. +{xp} XP {stat} si tu le fais maintenant.', 10, true),
('mentor', 'neutral', 't30', 'Le moment parfait pour {habit}, c''est maintenant. Dans {minutes_left} min il sera trop tard. +{xp} XP {stat} à la clé.', 8, true),
('mentor', 'neutral', 't30', 'Un Chasseur de rang {rank} ne laisse pas filer +{xp} XP. {habit}, {minutes_left} minutes.', 8, true),
('mentor', 'neutral', 't30', 'Petit rappel : {habit} t''attend. C''est 5 minutes d''effort contre +{xp} XP {stat}. Bon deal.', 7, true),
('mentor', 'neutral', 't30', 'Ta stat {stat} stagne depuis ce matin. {habit} la fera bouger. {minutes_left} min restantes.', 7, true),

('system', 'neutral', 't30', '[SYSTÈME] La quête « {habit} » expire dans {minutes_left} min. Récompense : +{xp} XP {stat}. Pénalité : -{penalty} XP.', 10, true),
('system', 'neutral', 't30', '[SYSTÈME] Quête quotidienne non complétée : « {habit} ». Fenêtre de validation : {minutes_left} minutes.', 8, true),
('system', 'neutral', 't30', '[SYSTÈME] Alerte. Objectif « {habit} » en attente. Statut du joueur : niveau {level}, rang {rank}. Échec = -{penalty} XP.', 7, true),
('system', 'neutral', 't30', '[SYSTÈME] Le donjon « {habit} » ferme ses portes dans {minutes_left} min. Butin : +{xp} XP {stat}.', 8, true),
('system', 'neutral', 't30', '[SYSTÈME] Rappel de mission : « {habit} ». Taux de réussite requis pour maintenir le rang {rank} : 100%.', 6, true),

('streak', 'hype', 't30', '🔥 Jour {streak} en jeu. {habit} dans les {minutes_left} prochaines minutes et la série continue.', 8, true),
('streak', 'hype', 't30', 'Ta série de {streak} jours repose sur {habit}. Ne la laisse pas mourir pour {minutes_left} minutes de flemme.', 7, true),

-- =========================================================
-- T-15 — Escalade niveau 1 (1 notification ignorée → Système plus sec)
-- =========================================================
('system', 'neutral', 't15', '[SYSTÈME] DERNIER APPEL. « {habit} » expire dans {minutes_left} min. -{penalty} XP et streak en danger.', 10, true),
('system', 'neutral', 't15', '[SYSTÈME] Tu as ignoré le premier avertissement. « {habit} » : {minutes_left} minutes avant échec de quête.', 9, true),
('system', 'harsh', 't15', '[SYSTÈME] Analyse : tu as vu la notification et tu as scrollé. « {habit} », {minutes_left} min. Décide.', 8, true),
('system', 'neutral', 't15', '[SYSTÈME] État critique. Quête « {habit} » : {minutes_left} min restantes. Un rang {rank} peut mieux faire.', 7, true),
('system', 'harsh', 't15', '[SYSTÈME] Le temps ne négocie pas. « {habit} » — {minutes_left} minutes. Récompense +{xp} XP ou pénalité -{penalty} XP.', 7, true),

('mentor', 'neutral', 't15', 'Dernière fenêtre pour {habit}. Fais-le en version courte s''il le faut, mais fais-le. {minutes_left} min.', 8, true),
('mentor', 'neutral', 't15', 'Je sais que tu n''as pas envie. C''est exactement pour ça que ça vaut +{xp} XP. {habit}, maintenant.', 8, true),
('mentor', 'neutral', 't15', 'La version de toi de demain te remerciera ou te maudira dans {minutes_left} minutes. {habit}.', 7, true),

-- =========================================================
-- T-15 — Escalade niveau 2 (2+ ignorées → le Boss parle)
-- =========================================================
('boss', 'harsh', 't15', '👹 Le Boss de la Procrastination sourit. Encore {minutes_left} minutes d''inaction et « {habit} » lui appartient.', 10, true),
('boss', 'harsh', 't15', '👹 « Il va encore abandonner. Comme d''habitude. » Prouve-lui qu''il a tort. {habit}, {minutes_left} min.', 9, true),
('boss', 'harsh', 't15', '👹 Chaque quête que tu rates le rend plus fort. « {habit} » expire dans {minutes_left} min. À toi de voir qui gagne.', 8, true),
('boss', 'harsh', 't15', '👹 Il se nourrit de tes « demain ». {habit}. Maintenant. Ou -{penalty} XP et il rit.', 8, true),

-- =========================================================
-- Slump — remplace T30/T15 quand completion_rate_7d < 40%
-- (uniquement supportive, le Boss est muet)
-- =========================================================
('mentor', 'supportive', 't30', 'La semaine est dure, je sais. Juste {habit} aujourd''hui. Une seule quête. On reconstruit à partir de là.', 10, true),
('mentor', 'supportive', 't30', 'Pas besoin d''une journée parfaite. Juste {habit}. Deux minutes de version minimale comptent aussi. +{xp} XP.', 9, true),
('mentor', 'supportive', 't30', 'Un Chasseur ne se juge pas sur ses chutes mais sur ses retours. {habit} est ta porte de retour. {minutes_left} min.', 8, true),
('mentor', 'supportive', 't15', 'Encore {minutes_left} min pour {habit}. Fais-le mal, fais-le vite, mais fais-le. C''est ça, reconstruire.', 9, true),
('mentor', 'supportive', 't15', 'Ce soir tu peux te coucher avec une victoire : {habit}. Petite, mais réelle. {minutes_left} minutes.', 8, true),
('system', 'supportive', 't30', '[SYSTÈME] Mode reconstruction activé. Une seule quête prioritaire : « {habit} ». Les pénalités sont secondaires. Toi, non.', 7, true),

-- =========================================================
-- Événements aléatoires
-- =========================================================
('system', 'hype', 'event_potion', '[SYSTÈME] 🧪 Objet rare détecté : Potion d''Énergie. Effet : XP ×2 aujourd''hui si toutes les quêtes sont complétées.', 10, true),
('system', 'hype', 'event_potion', '[SYSTÈME] 🧪 Une Potion d''Énergie brille dans ton inventaire. Journée parfaite = tout ton XP doublé. Ne la gâche pas.', 8, true),
('mentor', 'hype', 'event_potion', '🧪 Jour de chance : Potion d''Énergie active. Finis tes 5 quêtes et repars avec le double d''XP. Ça, c''est un lundi rentable.', 7, true),

('system', 'hype', 'event_chest', '[SYSTÈME] 💰 Coffre mystère apparu. Condition d''ouverture : 3 quêtes complétées aujourd''hui. Contenu : inconnu.', 10, true),
('system', 'hype', 'event_chest', '[SYSTÈME] 💰 Un coffre verrouillé est apparu dans le Hub. Clé : 3 habitudes avant minuit.', 8, true),

('system', 'hype', 'event_rush', '[SYSTÈME] ⚡ Heure de rush : « {habit} » vaut XP ×2 si complétée avant 12h00. Le Système récompense les lève-tôt.', 10, true),
('system', 'hype', 'event_rush', '[SYSTÈME] ⚡ Bonus matinal actif sur « {habit} ». Avant midi : +{xp} XP ×2. Après : tarif normal.', 8, true),

('system', 'harsh', 'event_cursed', '[SYSTÈME] 🌑 Jour maudit. Toutes les pénalités sont doublées jusqu''à minuit. Le Système conseille la prudence… et le travail.', 10, true),
('system', 'harsh', 'event_cursed', '[SYSTÈME] 🌑 Une aura sombre plane sur tes quêtes : pénalités ×2 aujourd''hui. Les vrais rangs {rank} ne tremblent pas.', 8, true),

-- =========================================================
-- Boss — cycle de vie
-- =========================================================
('boss', 'harsh', 'boss_spawn', '👹 UN BOSS EST APPARU. Le Boss de la Procrastination (3 PV) se dresse devant toi. Arme pour le vaincre : 3 journées parfaites. S''il survit 14 jours, il dévore 10% de ta meilleure stat.', 10, true),
('boss', 'harsh', 'boss_spawn', '👹 Trois jours de dérive ont ouvert une faille. Le Boss de la Procrastination en sort. PV : {boss_hp}. Il ne partira pas tout seul.', 8, true),
('system', 'neutral', 'boss_spawn', '[SYSTÈME] ⚠️ Donjon d''urgence ouvert : « Boss de la Procrastination ». PV : {boss_hp}/3. Chaque journée parfaite inflige 1 dégât. Échec du raid dans 14 jours = -10% XP sur ta meilleure stat.', 9, true),

('boss', 'hype', 'boss_damage', '👹 COUP CRITIQUE. Ta journée parfaite lui arrache 1 PV. Il lui en reste {boss_hp}. Il commence à douter.', 10, true),
('system', 'hype', 'boss_damage', '[SYSTÈME] Dégât infligé au Boss : -1 PV ({boss_hp} restants). Continue le combo.', 8, true),

('boss', 'harsh', 'boss_heal', '👹 Ta journée ratée l''a nourri. Le Boss régénère 1 PV ({boss_hp}/3). Il te dit merci.', 10, true),

('system', 'hype', 'boss_defeat', '[SYSTÈME] 🏆 BOSS VAINCU. Butin : +150 XP répartis, objet rare débloqué. Le Système enregistre ta victoire. Rang {rank}, tu montes.', 10, true),
('boss', 'hype', 'boss_defeat', '👹 « Impossible… » Ce sont ses derniers mots. Boss de la Procrastination : éliminé. +150 XP. Titre débloqué.', 9, true),

('boss', 'harsh', 'boss_deadline', '👹 Plus que 3 jours avant qu''il ne dévore 10% de ta stat {stat}. Trois journées parfaites. C''est lui ou toi.', 10, true),

-- =========================================================
-- Streaks — progression, paliers, boucliers
-- =========================================================
('streak', 'hype', 'streak_progress', '🔥 Jour {streak}. Plus que {days_to_title} jours avant le titre « {title_next} ». Tu es en train de le faire pour de vrai.', 10, true),
('streak', 'hype', 'streak_progress', '🔥 {streak} jours d''affilée. La plupart des gens abandonnent au jour 3. Toi, tu vises « {title_next} » dans {days_to_title} jours.', 8, true),
('streak', 'hype', 'streak_progress', '🔥 Série : {streak} jours. Ton toi d''il y a un mois ne te reconnaîtrait pas. {days_to_title} jours avant « {title_next} ».', 7, true),

('streak', 'hype', 'streak_milestone', '🏅 TITRE DÉBLOQUÉ : « {title_next} ». {streak} jours de discipline. Le Système s''incline. Prochain palier en vue.', 10, true),
('system', 'hype', 'streak_milestone', '[SYSTÈME] Palier atteint : {streak} jours consécutifs. Titre « {title_next} » ajouté à ta collection. Peu de Chasseurs arrivent ici.', 9, true),
('mentor', 'hype', 'streak_milestone', '{streak} jours. Tu te souviens du jour 1 ? Moi oui. Titre « {title_next} » débloqué — porte-le fièrement.', 7, true),

('system', 'neutral', 'streak_shield', '[SYSTÈME] 🛡️ Bouclier de Streak consommé. Ta série de {streak} jours est intacte. Boucliers restants : {shields}. Reviens demain.', 10, true),
('mentor', 'supportive', 'streak_shield', '🛡️ Journée ratée, série sauvée. Ton bouclier a tenu ({shields} restants). Une chute amortie n''est pas une chute. Demain, on repart.', 9, true),

-- =========================================================
-- Rédemption (streak cassé sans bouclier)
-- =========================================================
('mentor', 'supportive', 'redemption', 'Ta série de {streak} jours est tombée. Ça fait mal, je sais. Quête de Rédemption disponible : 3 journées parfaites pour en restaurer la moitié. Les légendes ont toutes un chapitre sombre.', 10, true),
('system', 'supportive', 'redemption', '[SYSTÈME] Série interrompue. Protocole de Rédemption activé : 3 journées parfaites consécutives = restauration de 50% de la série. La quête commence maintenant.', 9, true),
('mentor', 'supportive', 'redemption', 'Un streak cassé ne supprime pas {streak} jours de preuves que tu en es capable. Quête de Rédemption : 3 jours pour tout relancer.', 8, true),

-- =========================================================
-- Journée parfaite
-- =========================================================
('system', 'hype', 'perfect_day', '[SYSTÈME] ✨ JOURNÉE PARFAITE. Toutes les quêtes complétées. Bonus ×1.5 appliqué. Streak global : {streak} jours.', 10, true),
('streak', 'hype', 'perfect_day', '✨ 100% aujourd''hui. Jour {streak} de la série. Ferme l''app et va savourer, tu as gagné ta soirée.', 9, true),
('mentor', 'hype', 'perfect_day', 'Journée parfaite. C''est exactement comme ça qu''on devient un monstre : un jour banal parfaitement exécuté, {streak} fois de suite.', 8, true),

-- =========================================================
-- Level up & Rank up
-- =========================================================
('system', 'hype', 'level_up', '[SYSTÈME] ⬆️ {stat} passe au niveau {level}. Ta progression est enregistrée. Les autres stats réclament la même attention.', 10, true),
('mentor', 'hype', 'level_up', '⬆️ {stat} niveau {level}. Ce n''est pas l''app qui a monté — c''est toi. Le compteur ne fait que le constater.', 8, true),

('system', 'hype', 'rank_up', '[SYSTÈME] 🌟 CHANGEMENT DE RANG : tu es désormais un Chasseur de rang {rank}. Peu franchissent ce seuil. De nouvelles quêtes t''attendent.', 10, true),
('system', 'hype', 'rank_up', '[SYSTÈME] 🌟 Réévaluation complète… Rang {rank} confirmé. Le Système t''observait. Il n''est pas déçu.', 8, true),

-- =========================================================
-- Pénalité appliquée (minuit)
-- =========================================================
('system', 'neutral', 'penalty', '[SYSTÈME] Quête « {habit} » échouée. -{penalty} XP {stat}. Le Système ne juge pas. Il compte. Demain, nouvelle quête.', 10, true),
('system', 'neutral', 'penalty', '[SYSTÈME] Rapport de minuit : « {habit} » non complétée. Pénalité : -{penalty} XP. Donnée enregistrée, page tournée.', 8, true),

-- =========================================================
-- Morning brief (08:00 — résumé du jour)
-- =========================================================
('system', 'neutral', 'morning_brief', '[SYSTÈME] Bonjour, Chasseur de rang {rank}. Quêtes du jour chargées. Streak actuel : {streak} jours. Le donjon est ouvert.', 10, true),
('mentor', 'neutral', 'morning_brief', 'Nouveau jour, nouvelles quêtes. Ta seule mission : être à 100% ce soir. Streak en cours : {streak} jours. On y va.', 8, true),
('system', 'hype', 'morning_brief', '[SYSTÈME] Jour {streak}+1 potentiel. Les quêtes t''attendent. Rappel : un rang {rank} se maintient chaque jour, pas une fois par semaine.', 7, true);

-- =============================================================
-- ~70 templates. Règles d'usage (moteur, cf. SPEC §4.4) :
--  * slump (7j < 40%) → SELECT ... WHERE tone = 'supportive'
--  * 1 ignorée → persona = 'system' sur t15
--  * 2 ignorées → persona = 'boss' sur t15
--  * régulier (7j > 85%) → t15 uniquement, weight des tons hype réduits
--  * anti-répétition : exclure les 5 derniers template_id de notification_log
-- =============================================================
