# 🗺️ ROADMAP — LEVELUP

> **Statut : proposition.** Ce fichier n'amende pas `SPEC.md`. Les briques marquées
> ⚠️ touchent une règle verrouillée et attendent ton GO explicite avant d'être spécifiées.
>
> Ordre établi pour **ton usage perso** (un seul joueur). Tout ce qui est multijoueur
> est repoussé au moment où l'app aura des utilisateurs et sera sur l'App Store.

---

## 0. Ce qui existe déjà (avant d'écrire une ligne de plus)

Environ un tiers du doc de vision est **déjà en production**. Le lire d'abord évite de
reconstruire l'existant.

| Idée du doc | Statut |
|---|---|
| Niveau global & XP | ✅ SPEC §3.2 / §3.3 |
| Quêtes quotidiennes & hebdomadaires | ✅ M1 / M4 |
| Streaks | ✅ §3.4 — avec boucliers |
| Stats (Force, Intelligence, …) | ✅ 5 stats : `FOR` `INT` `SAG` `PRO` `END` |
| Rangs E → S | ✅ §3.3 — **il manque « Monarch »** au-dessus de S |
| Titres & badges | ✅ M4 |
| Quêtes surprises | ✅ §3.6 — événements aléatoires |
| Succès cachés | 🟡 Quête Secrète quotidienne (§3.14). Les **Reliques** (succès permanents) manquent |
| Coffres & loot | 🟡 Plomberie faite (`grant_random_item`, inventaire, 5 items). Manque le **contenu** et le **Gold** |
| Mentor avec personnalité, notifications immersives | ✅ §4 — moteur de personas + escalade, **sans IA** |
| Timeline de vie | 🟡 Journal du Chasseur hebdo (§3.15) + export image. La timeline longue manque |
| Boss | 🟡 **1 sur 10** (voir ci-dessous) |
| Cinématiques lors des gros niveaux | ❌ Le serveur émet déjà l'événement — **rien ne s'affiche** |
| Arbre de compétences, Classes, Équipement, Battle Pass, Prestige | ❌ |
| Personnage évolutif (le physique reflète les habitudes) | ❌ — **c'est la thèse du doc** |
| Musculation (carnet, charges, PR) | ❌ |
| Donjons de 30 jours | ❌ ⚠️ « Donjon Instantané » (§3.10) occupe déjà ce mot et veut dire autre chose |
| PNJ donneurs de quêtes | ❌ — déconseillé, voir §3 |
| Guildes, raids, classements, Hall of Fame | ⏸ Social — le raid duo est déjà spécifié (§3.13) |

### Les Boss : 1 sur 10

Ton doc liste 10 boss. **Le « boss d'endurance » que tu décris est exactement celui qui
tourne** (PV, il se soigne quand tu décroches, il expire à 14 jours en emportant de l'XP).
Les 8 autres variantes solo sont de la **pure logique Postgres sur une table qui existe déjà** :
c'est le meilleur rapport plaisir / effort de tout le document.

| Boss | Statut |
|---|---|
| Endurance | ✅ **c'est le boss actuel** |
| Narratifs (Procrastination, Peur, Ego, Fatigue, Distraction) | 🟡 un seul : la Procrastination |
| Points faibles quotidiens · Combo · Adaptatif · Phases · Bouclier · Élémentaire · Contre-la-montre | ❌ |
| Coopératifs | ⏸ Social |

---

## 1. L'ordre de construction

### M8 — Planification par quota *(déjà conçu, à finir)*
Récurrence (journalière / hebdo / mensuelle / annuelle / unique) + fréquence 1-10, pénalités
en fin de période, journée neutre. Amende §3.5 + §5.

**Pourquoi en premier :** c'est le socle. Tout le reste se greffe sur le modèle de quête.
Construire les boss, les donjons ou la muscu sur l'ancien modèle « jours fixes » puis migrer
serait du travail jeté.

---

### M9 — Les Moments *(petit, énorme retour)*
Rank-up plein écran, extraction d'Ombre, montée de niveau, victoire de boss. Reliquat du M7.

**Pourquoi si haut :** ces événements **se produisent déjà** côté serveur — et ne s'affichent
nulle part. Tu passes de rang et… rien. C'est un pic émotionnel **déjà payé** qu'on jette.
Les sons viennent d'être câblés et attendent leur visuel. Coût faible, effet immédiat sur
tout le reste.

**Done :** je passe de rang → l'écran s'arrête et le Système l'annonce.

---

### M10 — L'Arsenal des Boss
Les 8 variantes solo : boss narratifs (Peur, Ego, Fatigue, Distraction, Scroll, Sommeil),
point faible du jour, combo (enchaîner dans la journée = dégâts ×2, ×3), boss **adaptatif**
(il cible ta stat la plus faible et génère des quêtes liées), phases tous les 20 % de PV,
bouclier à casser, efficacité élémentaire (lecture → boss Mental, salle → boss Brutal),
contre-la-montre.

**Pourquoi ici :** zéro asset, zéro nouvel écran — de la règle de jeu sur `boss_fights`,
qui existe et est testée. C'est ce qui donne des **enjeux** à la boucle quotidienne que tu
fais déjà tous les jours.

**Done :** un boss adaptatif spawn, cible ma stat la plus faible, et un combo de 3 quêtes
dans la journée le blesse davantage.

---

### M11 — Le Chasseur *(personnage + classes + Monarch)*
- **Silhouette évolutive** : elle s'élargit avec `FOR`, s'auréole avec `INT`, s'affine avec
  `END`… Le composant `ShadowSilhouette` existe déjà → **V1 sans commander le moindre asset**.
- **Classe dérivée**, jamais choisie : ta répartition de stats *fait* de toi un Berserker,
  un Scholar, un Assassin. Le personnage devient un **miroir**, pas un avatar.
- **Rang Monarch** au-dessus de S (§3.3 s'arrête à S — plus d'horizon passé 50).

**Pourquoi ici :** c'est la **thèse de ton doc** (« le personnage est le reflet de la vraie
vie »). Tu l'avais repoussé au grand public — je pense que c'est une erreur : c'est ce qui
sépare ton app d'un tracker, et ça vaut d'abord pour **toi**.

---

### M12 — Le Carnet *(musculation)*
Séances, exercices, charges, séries/reps, records personnels, volume → XP `FOR`.

**Pourquoi ici :** c'est le lien IRL → stat le plus **concret** du doc entier. Mais c'est un
vertical complet (base d'exercices, saisie rapide, détection de PR) — donc après les briques
transverses. ⚠️ L'XP au volume touche la formule verrouillée §3.2.

---

### M13 — Les Donjons *(arcs de 30 jours)*
Un objectif long, une narration, des paliers, un boss de fin. ⚠️ **À renommer** : « Donjon
Instantané » (§3.10) désigne déjà la version 2 minutes d'une habitude.

---

### M14 — Reliques & Mémoire
Reliques (succès permanents, cachés), timeline de vie, **récap annuel** (« Wrapped »).
S'appuie sur le Journal du Chasseur, qui existe déjà.

---

### M15 — Arbre de compétences
Perks qui **modifient les règles** (ex. « +10 % d'XP avant 8 h », « le 1er bouclier ne se
consomme pas »). Après les classes, sinon on ne sait pas sur quoi les greffer.

---

### M16 — Économie & cosmétiques
Gold, coffres, magasin, équipement cosmétique. Nécessite des **assets** et une DA stabilisée.
Solo, un cosmétique que personne ne voit a une traction faible : c'est pour ça que ça arrive tard.

---

### M17 — Saisons & Ascension ⚠️
Arcs de 90 jours à thème. Et le « Prestige » **repensé** — voir §2.

---

### Plus tard — quand l'app aura des utilisateurs (App Store)
Guildes (le raid duo §3.13 est déjà spécifié), boss de guilde, boss coopératifs, classements,
raids mondiaux, Hall of Fame. Plus le **Mentor IA** (voir §2).

---

## 2. Décisions qui t'appartiennent

**⚠️ Le Prestige contredit frontalement le SPEC §8.**
§8 dit : *« Ne jamais faire descendre un niveau ni retirer un titre/Ombre (plancher
psychologique). »* C'est le contrat émotionnel de l'app : ce que tu as gagné est inviolable.
Le prestige, lui, dit « rends tout pour un bonus permanent ».
**Ma proposition — l'Ascension :** tu ne perds jamais rien. Arrivé au rang Monarch, tu ouvres
une **couche au-dessus** (modificateurs permanents, quêtes d'un autre ordre). Même dopamine,
zéro trahison. Si tu veux le vrai reset, il faut amender le §8 — et c'est ton appel, pas le mien.

**⚠️ La muscu au volume touche la formule d'XP (§3.2, verrouillée).** Il faut décider comment
tonnage → XP sans casser l'équilibre des 5 stats.

**⚠️ Le Mentor IA contredit « Zéro IA en V1 ».** Honnêtement : le moteur de personas + escalade
(§4) livre déjà 90 % du ressenti « mentor qui te connaît », sans latence, sans coût, sans envoyer
tes données. Je le garderais tard et délibéré.

**Le personnage : tu l'avais repoussé.** Ton doc en fait la thèse. Je le remonte en M11 — dis-moi
si tu maintiens le report.

---

## 3. Ce que je déconseille

**Le Battle Pass.** C'est une coquille de rétention/monétisation pour un jeu vivant avec une base
d'utilisateurs. Seul, un « pass » que tu t'achètes à toi-même ne veut rien dire. Les **Saisons**
(M17) gardent l'intérêt — l'arc thématique — et jettent la coquille.

**Les PNJ donneurs de quêtes.** Le Système **est déjà** ton PNJ : il te parle, il durcit le ton,
il te connaît. Ajouter des personnages secondaires diluerait la seule voix qui a de l'autorité.
