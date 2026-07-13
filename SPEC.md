# ⚔️ LEVELUP — Habit Tracker RPG (Solo Leveling style)

> Spec de référence v1.2 — à poser à la racine du repo. Claude Code doit s'y conformer.
> Principe : **aucune IA en V1.** Tout le "vivant" vient d'un moteur de règles + banque de templates.

---

## 1. Vision

Un habit tracker où la vie est un MMO RPG : chaque habitude est une quête, chaque domaine de vie une statistique, chaque jour une chance de monter en rang. Les notifications ne rappellent pas — elles **racontent** (mentor, système, boss, streak).

**Anti-objectif :** ne pas devenir Habitica (surcharge, DA enfantine). Ton : sombre, épuré, Solo Leveling ("Système" froid + moments épiques).

---

## 2. Stack technique

| Couche | Choix | Raison |
|---|---|---|
| Frontend | **Next.js 15 (App Router) en PWA** | Stack maîtrisée, gratuit, installable iOS/Android |
| PWA | `next-pwa` ou service worker custom + manifest | Push + offline shell |
| Notifications | **Web Push (VAPID)** via lib `web-push` | Gratuit, pas de compte Apple. iOS ≥ 16.4 : PWA installée requise |
| Backend/DB | **Supabase** (Postgres + Auth + Edge Functions + pg_cron) | Gratuit, RLS, cron natif |
| Scheduling | `pg_cron` → Edge Function `send-notifications` (toutes les 5 min) | Le serveur décide quoi envoyer et sur quel ton |
| Hosting | **Vercel** (free tier) | CI/CD auto |
| Styling | Tailwind + design system custom (voir §9) | |

**Règle d'or : toute la logique XP/niveaux/streaks/pénalités est calculée côté serveur** (fonctions Postgres + Edge Functions). Le client ne fait qu'afficher et check-in. Zéro triche, zéro désync.

---

## 3. Game design — chiffres verrouillés

### 3.1 Les 5 statistiques

| Stat | Code | Domaine | Exemples |
|---|---|---|---|
| Force | `FOR` | Sport / physique | muscu, créatine, cardio |
| Intelligence | `INT` | Apprentissage | lecture, formation, langue |
| Sagesse | `SAG` | Mental | méditation, journaling, gratitude |
| Productivité | `PRO` | Travail | deep work, inbox zero, no-scroll |
| Endurance | `END` | Récupération | sommeil avant 23h, hydratation, pas d'alcool |

Chaque habitude est rattachée à **une** stat.

### 3.2 XP

- Difficulté d'une habitude : **Facile +10 XP / Moyenne +25 XP / Difficile +50 XP**
- Complétion avant l'heure limite → XP complet sur la stat
- Non-complétion à minuit → **pénalité = 40% de l'XP de l'habitude**, retirée à la stat (plancher 0, on ne descend jamais de niveau)
- Multiplicateurs (cumulatifs, cap ×3) :
  - Journée parfaite (100% des habitudes) : **×1.5 sur la dernière habitude complétée**
  - Potion d'Énergie active : **×2 sur toute la journée**
  - Streak ≥ 21 j sur l'habitude : **×1.2 permanent**

### 3.3 Niveaux & Rangs

- XP requis pour passer une stat au niveau N : `100 × N^1.5` (arrondi)
  - Niv 1→2 : 100 XP · 2→3 : 283 · 5→6 : 1 118 · 10→11 : 3 162
- **Niveau global** = moyenne des 5 niveaux de stats (arrondi bas)
- **Rang du Chasseur** selon niveau global :

| Rang | Niveau global |
|---|---|
| E | 1–4 |
| D | 5–9 |
| C | 10–19 |
| B | 20–34 |
| A | 35–49 |
| **S** | 50+ |

Le passage de rang = moment épique (plein écran, animation "Système").

### 3.4 Streaks

- **Streak par habitude** : jours consécutifs de complétion
- **Streak global** : jours consécutifs de journées parfaites
- Paliers de streak global → **Titres** :

| Jours | Titre |
|---|---|
| 7 | Éveillé |
| 21 | Régulier |
| 42 | Discipline de Fer |
| 66 | Inarrêtable |
| 100 | Monarque |

- **Bouclier de Streak 🛡️** : +1 gagné tous les 10 jours de streak global (max 3 en stock). Consommé automatiquement pour protéger une journée ratée. *Mécanique anti-churn n°1 : un streak cassé sans filet = désinstallation.*

### 3.5 Quêtes

#### 3.5.1 Planification par QUOTA (amendement M8 — remplace les jours fixes)

Une quête n'est plus attachée à des jours de la semaine, mais à un **quota par période** :

| Champ | Valeurs |
|---|---|
| `recurrence` | `daily` · `weekly` · `monthly` · `yearly` · `once` |
| `frequency` | 1 à 10 — **nombre de fois par période** |
| `temporary` | booléen — quête à durée limitée (archivée après sa période) |
| `stat` (arc) | FOR / INT / SAG / PRO / END |
| `difficulty` | easy / medium / hard (XP §3.2 inchangé) |

- **Quota libre** : une quête est proposable **tant que son quota de la période courante n'est pas rempli**. Elle n'est due aucun jour précis. Ex. `weekly + 3` = 3 fois dans la semaine, quand tu veux.
- **Périodes** (toujours en TZ user) : jour civil · semaine ISO (lundi→dimanche) · mois civil · année civile.
- `once` = quête unique, disparaît une fois complétée.

#### 3.5.2 Pénalités — jugement en FIN DE PÉRIODE

Le Tribunal de minuit (§3.9) ne peut plus juger chaque soir ce qui n'est pas dû chaque soir :

- **Quotas journaliers** : jugés chaque nuit. Manquant = `(quota − complétions) × 40 % de l'XP`.
- **Quotas hebdo / mensuel / annuel** : jugés **à la clôture de leur période** (dimanche minuit, fin de mois, fin d'année). Même formule sur le manquant.
- Idempotence : une clôture de période ne peut pas être appliquée deux fois (contrainte unique `habit_id + période`).

#### 3.5.3 Journée parfaite, streak, Boss

La boucle quotidienne reste **inchangée** et ne regarde que ce qui est dû aujourd'hui :

- **Journée parfaite** = tous les **quotas journaliers** remplis **ET** toutes les todos du jour faites.
- ⚠️ **Journée neutre** : si aucune obligation n'est due aujourd'hui (aucun quota journalier, aucune todo), la journée n'est **ni parfaite ni ratée** — le streak ne monte pas, ne casse pas, aucun bouclier n'est consommé. (Ferme la faille « aucune quête aujourd'hui = streak gratuit ».)
- Le streak global, le Boss (§3.7) et le malus visible (§3.16) continuent de se calculer sur cette base journalière.

#### 3.5.4 Quêtes générées par le Système (inchangé)

- **Hebdomadaires** (générées lundi 00:00, 2 par semaine) : "Complète {n} quêtes de {stat} cette semaine". Récompense : XP bonus (+100) OU item cosmétique.
- **Quête de rédemption** : proposée après un streak cassé sans bouclier — "3 journées parfaites d'affilée pour restaurer 50% de ton ancien streak".

### 3.6 Événements aléatoires 🎲

Tirage quotidien à 08:00 (Edge Function `daily-tick`), probabilités :

| Événement | Proba | Effet |
|---|---|---|
| 🧪 Potion d'Énergie | 12% | ×2 XP si journée parfaite aujourd'hui |
| 💰 Coffre mystère | 8% | Item cosmétique aléatoire si ≥ 3 habitudes complétées |
| ⚡ Heure de rush | 10% | Une habitude tirée au sort vaut ×2 XP si faite avant 12h |
| 🌑 Jour maudit | 5% | Pénalités doublées aujourd'hui (tension = engagement) |
| Rien | 65% | — |

### 3.7 Boss 👹

- **Déclencheur** : 3 jours consécutifs avec < 50% de complétion → spawn du **Boss de la Procrastination** (HP = 3)
- Chaque journée parfaite lui retire 1 HP. Chaque jour < 50% lui rend 1 HP (max 3).
- **Victoire** : +150 XP répartis, titre "Tueur de Boss" (première fois), item rare
- **Si le boss reste 14 jours** : il disparaît et emporte 10% de l'XP de la stat la plus haute (annoncé dès le spawn — enjeu clair)
- Boss thématiques futurs : Boss du Sommeil (END basse), Boss du Scroll (PRO basse)…

### 3.8 To-Do quotidienne & rituel du soir 📋

En plus des habitudes récurrentes, le Chasseur planifie ses **tâches ponctuelles** (todos) — la veille au soir.

- **Rituel du soir (21:00, notification dédiée)** : "Prépare tes quêtes de demain." Créer sa todo du lendemain = mini-quête récurrente **+10 XP PRO** (l'acte de planifier est lui-même une habitude).
- Chaque todo : titre, stat associée (défaut PRO), difficulté (mêmes paliers XP que les habitudes : 10/25/50), deadline optionnelle.
- Les todos comptent dans le % de complétion de la journée (journée parfaite = 100% habitudes **ET** todos).
- **Morning brief (08:00)** : notification + écran dédié dans le Hub qui récapitule — quêtes du jour (habitudes), todos planifiées la veille, événement aléatoire du jour, boss actif, quête secrète disponible, streak en cours. C'est le "chargement du donjon" du matin.

### 3.9 Pénalités franches — le Tribunal de minuit ⚖️

Le Système ne juge pas les mauvaises semaines (mode slump = rappels bienveillants), mais **il ne laisse rien passer sur les journées d'abus**. À `midnight-close` :

- Habitude/todo ratée : **-40% de son XP** (règle de base, §3.2)
- **Pénalité progressive** : 2ᵉ jour consécutif < 50% → pénalités ×1.5 ; 3ᵉ jour et + → pénalités **×2** (et le Boss spawn)
- **Journée d'abus** (< 50% de complétion hors mode slump) : rapport de minuit en ton `harsh` — franc, factuel, sans insulte : "[SYSTÈME] Bilan : 2 quêtes sur 7. -85 XP. Tu vaux mieux que cette journée. Le compteur repart à 08:00."
- Le **malus visible** (§3.15) s'aggrave d'un cran
- Exception : si `is_slump`, la pénalité de base s'applique mais **jamais** le multiplicateur ni le ton harsh — on ne frappe pas quelqu'un à terre, on frappe quelqu'un qui se relâche.

### 3.10 Donjon Instantané ⚡ (anti-procrastination n°1)

Quand une habitude approche de l'expiration (T-15) et que le contexte indique un risque d'échec, le Système propose :

> "⚡ Donjon express : version 2 minutes de {habit}. Récompense : 50% de l'XP, streak intégralement sauvé."

- Chaque habitude définit à la création sa **version minimale** ("lire 2 pages", "5 pompes", "2 min de méditation")
- Complétion express : 50% XP, streak préservé, compte comme complétée pour la journée parfaite
- Limite : 2 donjons express / jour (sinon tout devient express)
- *Justification : la procrastination naît de la taille perçue de la tâche. Réduire la porte d'entrée sauve le streak, et une fois lancé, la version complète suit souvent.*

### 3.11 L'Armée des Ombres 🌑

Chaque habitude atteignant **100 complétions** devient une **Ombre** que le Chasseur "extrait" (animation d'extraction plein écran, façon rituel).

- L'Ombre porte le nom de l'habitude, un grade (100 → Soldat, 250 → Chevalier, 500 → Général, 1000 → Maréchal) et une silhouette générée parmi un set d'assets
- L'écran Profil affiche **l'Armée** : la preuve visuelle et permanente de qui tu es devenu
- Les Ombres ne se perdent jamais (règle du plancher psychologique)
- Bonus passif : chaque Ombre donne +2% XP permanent sur sa stat (cap +10%/stat)

### 3.12 Le Fantôme de toi-même 👻

Ton rival est **toi il y a 30 jours**.

- Matérialisation : `daily_snapshots` enregistre chaque nuit (niveau global, niveaux de stats, streak, taux 7j). Le Fantôme du jour J = ton snapshot du jour J-30, affiché comme un profil rival dans le Hub (silhouette translucide, mêmes stats qu'à l'époque).
- Comparaison permanente : "Toi : niv 14 · Ton Fantôme : niv 11 (+3)" + delta par stat
- Si le Fantôme te rattrape (tu as stagné/régressé sur 30 j) → événement spécial "Duel contre le Fantôme" : 7 jours pour reprendre l'avantage, sinon il "prend ta place" (malus visible + notification harsh)
- V1 : simple comparaison affichée dans le Hub + section dédiée dans le Journal du Chasseur. Le duel = V1.5.

### 3.13 Raid hebdomadaire de guilde ⚔️ (duo)

- Guilde minimale : **2 Chasseurs** (invitation par code)
- Chaque lundi, un **Boss de Raid** spawn (PV = 5) : il perd 1 PV chaque jour où **les deux** membres sont à 100%
- Victoire (5 PV avant dimanche minuit) : +200 XP chacun, item de raid exclusif, titre de guilde
- Échec : rien de perdu (le raid est un bonus, pas une punition — la pression sociale suffit)
- V1 : hors scope si pas de second utilisateur au lancement ; architecture prévue (tables `guilds`, `raid_fights`)

### 3.14 Quête Secrète quotidienne 🎁

- Chaque matin, `daily-tick` tire au sort **une habitude ou todo du jour** et lui attache un bonus caché (XP ×2, item, +1 bouclier, fragment de coffre)
- Le bonus n'est révélé **qu'à la complétion** : "🎁 Quête secrète accomplie ! {habit} cachait : +1 Bouclier de Streak."
- Le morning brief indique seulement : "Une quête du jour cache un trésor."
- *Récompense variable = dopamine de machine à sous, au service de la discipline.*

### 3.15 Journal du Chasseur 📜

- Chaque **dimanche 20:00**, génération d'un récap narratif par templates (zéro IA en V1) : quêtes complétées, XP gagnée/perdue, dégâts au boss, progression vs Fantôme, Ombres extraites, titres débloqués, taux de complétion vs semaine précédente
- Format : page stylisée "rapport du Système" + **export image** (1080×1920) partageable — boucle virale gratuite
- Archivé dans l'app (historique des semaines)

### 3.16 Malus visible 🩸

- Le **blason du Chasseur** (avatar V1 = blason héraldique par rang) reflète l'état courant :
  - État 0 (sain) : blason net, aura violette
  - État 1 (1 journée d'abus) : fissures légères
  - État 2 (2 jours consécutifs < 50%) : fissures profondes, aura grise
  - État 3 (boss actif) : blason sombre, aura rouge
- Restauration : chaque journée parfaite répare d'un cran
- Aucune perte définitive : le malus est un **signal d'état**, jamais une punition sur l'acquis

---

## 4. Moteur de notifications (le cœur du produit)

### 4.1 Architecture

```
pg_cron (*/5 min) → Edge Function send-notifications
  1. Sélectionne les habitudes dont l'heure limite approche (T-30, T-15) ou événements à annoncer
  2. Calcule le CONTEXTE utilisateur (voir 4.3)
  3. Choisit persona + tone selon les règles (4.4)
  4. Tire un template pondéré (jamais 2× le même consécutivement — table notification_log)
  5. Interpole les variables et envoie via web-push
```

### 4.2 Personas & banque de templates

Table `notification_templates` : `id, persona, tone, trigger_type, template, weight, active`

Variables disponibles : `{habit}`, `{xp}`, `{penalty}`, `{minutes_left}`, `{streak}`, `{title_next}`, `{days_to_title}`, `{boss_hp}`, `{stat}`

| Persona | Rôle | Exemple |
|---|---|---|
| 🧙 Mentor | Bienveillant, coach | "Il te reste {minutes_left} min pour {habit}. +{xp} XP {stat} si tu le fais maintenant." |
| ⚔️ Système | Froid, factuel (Solo Leveling) | "[SYSTÈME] La quête '{habit}' expire dans {minutes_left} min. Récompense : +{xp} XP. Pénalité : -{penalty} XP." |
| 👹 Boss | Menaçant, provoque | "Le Boss de la Procrastination te regarde abandonner '{habit}'. Prouve-lui qu'il a tort." |
| 🔥 Streak | Hype, momentum | "Jour {streak}. Plus que {days_to_title} jours avant le titre '{title_next}'." |

**V1 : minimum 8 templates par persona × déclencheur** (T-30, T-15, événement, boss, streak milestone, rédemption). ≈ 60–80 templates à écrire. C'est du copywriting, pas du code — livrable en seed SQL.

### 4.3 Contexte utilisateur (calculé à chaque envoi)

```
ignored_count_today, ignored_count_7d, completion_rate_7d,
current_streak, is_slump (completion_rate_7d < 40%),
is_regular (completion_rate_7d > 85%), boss_active
```

### 4.4 Règles d'escalade (remplace l'IA en V1)

| Condition | Comportement |
|---|---|
| Notification T-30 ignorée | T-15 passe en persona **Système** |
| 2 ignorées dans la journée | Dernier rappel en persona **Boss** |
| `is_regular` (7j > 85%) | Fréquence réduite : T-15 seulement, ton discret |
| `is_slump` (7j < 40%) | **Uniquement** templates `tone = 'supportive'` — jamais culpabilisant. Le Boss se tait. |
| Streak milestone atteint | Notification célébration persona Streak |
| Boss actif | 1 notif Boss max/jour (sauf slump) |

> 🔮 **V2 (IA)** : la seule chose qui change = l'étape 4 (tirage de template) devient un appel LLM avec le contexte 4.3 en prompt. L'architecture ne bouge pas.

---

## 5. Modèle de données (Supabase / Postgres)

```sql
-- Utilisateurs : gérés par Supabase Auth (auth.users) + table profile
profiles        (id FK auth.users, username, rank, global_level, created_at)
user_stats      (user_id, stat ENUM(FOR,INT,SAG,PRO,END), level, current_xp)
habits          (id, user_id, name, stat, difficulty ENUM(easy,medium,hard),
                 recurrence ENUM(daily,weekly,monthly,yearly,once), frequency INT 1-10,
                 temporary BOOL, deadline_time TIME, active, created_at)
                 -- M8 : le quota (recurrence + frequency) remplace schedule {days:[1..7]}
habit_logs      (id, habit_id, user_id, date, completions INT, completed_at, xp_earned, multiplier)
                 -- M8 : `completions` = nb de fois dans la journée (quota journalier > 1).
                 -- UNIQUE(habit_id,date) conservé = idempotence des crons (§8).
period_closures (id, user_id, habit_id, recurrence, period_start DATE, missing INT, xp_penalty INT)
                 -- M8 : idempotence du jugement de fin de période. UNIQUE(habit_id, period_start).
streaks         (user_id, habit_id NULLABLE /* NULL = streak global */,
                 current, best, shields INT, last_completed_date)
quests          (id, type ENUM(weekly,redemption), user_id, definition JSONB,
                 progress INT, target INT, reward JSONB, expires_at, status)
items           (id, name, type ENUM(potion,shield,skin,badge), rarity, icon, effect JSONB)
user_items      (user_id, item_id, quantity, equipped BOOL)
titles          (id, name, condition JSONB)
user_titles     (user_id, title_id, unlocked_at, equipped BOOL)
boss_fights     (id, user_id, boss_type, hp INT, max_hp INT, spawned_at, status)
events_log      (id, user_id, event_type, date, payload JSONB, resolved BOOL)
push_subscriptions (user_id, endpoint, keys JSONB, created_at)
notification_templates (id, persona, tone, trigger_type, template, weight, active)
notification_log (id, user_id, template_id, sent_at, clicked BOOL, habit_id)

-- Nouvelles mécaniques (§3.8 → §3.16)
todos           (id, user_id, title, stat DEFAULT 'PRO', difficulty, date /* jour d'exécution */,
                 deadline_time NULLABLE, completed_at, xp_earned, created_at /* la veille = rituel OK */)
habit_minimal   -- colonne sur habits : minimal_version TEXT (le "donjon express" de l'habitude)
                -- + colonne express_count_today gérée dans habit_logs (is_express BOOL)
daily_snapshots (user_id, date, global_level, stats JSONB, streak, completion_rate_7d)
                -- alimente le Fantôme (J-30) et le Journal
shadows         (id, user_id, habit_id, name, grade ENUM(soldat,chevalier,general,marechal),
                 asset_id, extracted_at, completions_at_extraction)
guilds          (id, name, invite_code, created_at)
guild_members   (guild_id, user_id, joined_at)  -- max 2 en V1
raid_fights     (id, guild_id, week_start, hp INT, max_hp INT, status)
journal_entries (id, user_id, week_start, payload JSONB, image_url NULLABLE, created_at)
secret_quests   (id, user_id, date, target_type ENUM(habit,todo), target_id, reward JSONB, revealed BOOL)
emblem_state    -- colonne sur profiles : emblem_damage INT (0-3), cf. malus visible §3.16
```

- **RLS activé partout** : chaque user ne voit que ses lignes.
- Fonctions Postgres : `complete_habit()`, `complete_todo()`, `apply_daily_penalties()` (avec multiplicateur progressif §3.9), `recompute_levels()`, `check_streaks()`, `extract_shadow()`, `take_daily_snapshot()`.
- Crons : `daily-tick` (08:00 : événements aléatoires, quête secrète, spawn boss, morning brief), `evening-ritual` (21:00 : rappel planification du lendemain), `midnight-close` (00:05 : pénalités progressives, streaks, boucliers, malus blason, snapshot quotidien), `weekly-tick` (lundi 00:00 : quêtes hebdo, raid ; dimanche 20:00 : Journal du Chasseur), `send-notifications` (*/5 min).

---

## 6. Écrans V1

1. **Onboarding** — création compte, création des 3 premières habitudes (avec leur version minimale "donjon express"), **installation PWA + activation push** (étape bloquante avec tuto iOS "Ajouter à l'écran d'accueil")
2. **Dashboard (Hub du Chasseur)** — blason (avec malus visible), rang + niveau global, radar chart des 5 stats, comparaison Fantôme, quêtes du jour (habitudes + todos) avec check-in 1 tap, streak global, événement du jour, indice de quête secrète, boss éventuel
3. **Morning Brief** — écran récap du matin (habitudes, todos de la veille, événement, boss, secret)
4. **Planification du soir** — création rapide de la todo du lendemain (rituel 21:00)
5. **Détail habitude / todo** — historique, streak, XP totale, version minimale, édition
6. **Quêtes** — hebdos en cours, rédemption, raid de guilde
7. **Profil / Inventaire / Armée des Ombres** — blason, titres, items, Ombres extraites, stats lifetime, comparaison Fantôme détaillée
8. **Journal du Chasseur** — récaps hebdo archivés + export image
9. **Paramètres** — heures de rappel, personas préférés (on/off Boss), notifications, guilde

---

## 7. Roadmap de build (ordre pour Claude Code)

| Milestone | Contenu | Critère de done |
|---|---|---|
| **M0 — Socle** | Repo, Next.js PWA, Supabase (schéma + RLS), auth, CI Vercel | Login + manifest installable |
| **M1 — Core loop** | CRUD habitudes, check-in, `complete_habit()`, XP/niveaux/stats, dashboard | Je check une habitude → XP monte, niveau calculé serveur |
| **M2 — Temps** | `midnight-close` : pénalités, streaks, boucliers, journée parfaite | Rater un jour applique la pénalité et consomme un bouclier |
| **M3 — Push** | Souscription web-push, `send-notifications`, banque de templates seed, règles d'escalade | Je reçois "T-30" sur iPhone (PWA installée) et le ton escalade si j'ignore |
| **M4 — Meta-game** | Quêtes hebdo, titres, événements aléatoires, quête secrète, boss, inventaire | Boss spawn après 3 mauvais jours et se bat ; un bonus caché se révèle à la complétion |
| **M5 — Journée complète** | Todos + rituel du soir + morning brief + donjon instantané + pénalités progressives + malus blason | Je planifie le soir, je reçois le brief à 8h, un donjon express sauve mon streak, une journée d'abus fissure le blason |
| **M6 — Identité** | Armée des Ombres (extraction + galerie), Fantôme (snapshots + comparaison Hub), Journal du Chasseur + export image | Une Ombre s'extrait à 100 complétions ; je vois mon Fantôme J-30 ; le récap du dimanche s'exporte en image |
| **M7 — Polish** | Animations rang-up/extraction, radar chart, onboarding complet, sons | Passage de rang = moment épique |
| **M8 — Social** | Guilde duo + raid hebdo | Le boss de raid perd 1 PV quand les 2 membres sont à 100% |

Chaque milestone = une branche + PR. Tests sur les fonctions Postgres (XP, pénalités, streaks) dès M1 — c'est là que vivent les bugs.

---

## 8. Contraintes & pièges connus

- **iOS push** : uniquement si PWA ajoutée à l'écran d'accueil (iOS ≥ 16.4). L'onboarding doit le rendre non-skippable. Prévoir fallback badge/email plus tard.
- **Fuseaux horaires** : stocker le TZ du user dans `profiles`, tous les crons raisonnent en TZ user (minuit local ≠ minuit UTC). Piège classique n°1.
- **Idempotence des crons** : `midnight-close` doit pouvoir tourner 2× sans doubler les pénalités (clé unique sur `habit_id + date` dans les logs).
- **Vercel free** : pas de cron long — tout le scheduling vit chez Supabase (pg_cron + Edge Functions).
- **Plancher psychologique** : on ne descend jamais de niveau, on ne perd jamais un titre. La punition = XP et streak, jamais l'acquis.

---

## 9. Direction artistique — DA "Système" (verrouillée)

Référence visuelle : mockups générés le 09/07/2026 (Hub ultra, Rank-up, Extraction d'Ombre, Boss, Morning Brief, Rituel du soir, Profil/Fantôme, Journal, Quêtes, planche d'assets). Les mockups sont la **cible**, le code s'en approche par touches (glow, blur, animations) en gardant la lisibilité prioritaire au quotidien.

### 9.1 Tokens

```css
:root {
  /* Fonds */
  --bg-abyss: #05050A;        /* fond global */
  --bg-panel: rgba(18, 16, 32, 0.55);  /* panneaux verre */
  --border-glow: rgba(124, 58, 237, 0.45);

  /* Accents */
  --violet: #7C3AED;          /* accent principal — ordre, Système */
  --cyan: #22D3EE;            /* accent secondaire — data, radar */
  --amber: #F59E0B;           /* événements, donjon express, urgence positive */
  --danger: #EF4444;          /* boss, jour maudit, pénalités — corruption rouge */
  --ghost: #93C5FD;           /* le Fantôme — bleu pâle translucide */

  /* Texte */
  --text-primary: #EDEDF7;
  --text-muted: #8B8AA3;
}
```

### 9.2 Règles

- **Typo display** (titres de rang, gros chiffres, [SYSTÈME]) : une condensée anguleuse (ex. *Orbitron*, *Rajdhani* ou *Chakra Petch* — bold, majuscules, letter-spacing large). **Typo texte** : *Inter*.
- **Composant signature "Fenêtre Système"** : panneau `--bg-panel` avec `backdrop-filter: blur(12px)`, bordure 1px `--border-glow`, **corner brackets** (4 équerres lumineuses aux coins, pseudo-éléments), header précédé de `[SYSTÈME]`, léger box-shadow violet externe. TOUT contenu modal/notification in-app passe par ce composant.
- **Hexagone partout** : rangs, chips de difficulté, cellules de PV de boss, frames d'icônes. Jamais de cercles pour les éléments de jeu.
- **Grammaire des couleurs** : violet = ordre/Système · cyan = données/progression · ambre = opportunité limitée dans le temps · rouge = danger/boss (le rouge "corrompt" le violet : glitch, RGB split léger) · bleu pâle translucide = le Fantôme.
- **Particules & fog** : uniquement sur les écrans "moments" (rank-up, extraction, boss, milestones) — canvas ou CSS léger. Le Hub quotidien reste sobre : glow des bordures + une nappe de gradient, pas de particules permanentes (batterie + lisibilité).
- **Complétion de quête** : slash lumineux traversant la ligne + flash bref du check hexagonal + incrément XP animé. C'est LA micro-interaction à soigner en premier.
- **Animations** : Framer Motion ; entrées de panneaux en fade+rise 200ms ; moments épiques en plein écran avec onde de choc radiale et light rays (SVG/CSS). Respecter `prefers-reduced-motion`.
- **Assets** : icônes stats/items/rangs recréées en SVG à partir de la planche générée (traits cohérents, glow via filter drop-shadow). Silhouettes d'Ombres : set de 4 SVG par grade.


---

## 10. Hors scope V1 (backlog explicite)

- IA génération de notifications (V2 — remplace le tirage de template)
- Duel contre le Fantôme (V1.5 — la comparaison Hub est en M6, le duel scénarisé plus tard)
- Guildes > 2 membres, classements publics, saisons de 90 jours
- App native / App Store
- Habitudes négatives ("ne pas faire X")
- Intégrations santé (Apple Health, etc.)
