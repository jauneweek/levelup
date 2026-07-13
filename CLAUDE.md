# CLAUDE.md — LEVELUP (Habit Tracker RPG)

## Contexte
Habit tracker gamifié style Solo Leveling. PWA Next.js + Supabase + Vercel. Zéro IA en V1 (moteur de règles + templates).

## Source de vérité
- **Lis `SPEC.md` avant toute tâche.** Toutes les formules (XP, niveaux, pénalités, streaks), le schéma de données, les mécaniques et la roadmap y sont verrouillés. Ne modifie JAMAIS une formule ou une règle de jeu sans me demander.
- Seed des notifications : `supabase/seed/notification_templates.sql` (ne pas réécrire les templates).
- DA : `SPEC.md §9` (tokens, composant Fenêtre Système, grammaire des couleurs) + mockups de référence dans `design/mockups/`. Utilise la skill frontend-design. Jamais de Tailwind générique : hexagones, corner brackets, glow violet.

## Milestone en cours
> **M8 — Planification par quota : FAIT** (branche `m8-planification`, migration `0008`). `recurrence` (daily/weekly/monthly/yearly/once) + `frequency` 1-10 + `temporary` remplacent `schedule.days` (colonne **supprimée**). Pénalités jugées en fin de période (`period_closures`, idempotent), **journée neutre**, quota journalier > 1 (`habit_logs.completions`). 203 assertions pgTAP vertes.
>
> **Prochain : gros travail UI/UX** (demandé par le user — l'UI actuelle ne lui plaît pas), puis **muscu**. Le reste de la roadmap est dans `ROADMAP.md`.
>
> Avant : **M7 — Polish** Fait : nav 4 onglets, 1ère passe de fidélité mockups, fix safe-area iOS, **perf** (région Vercel, loading.tsx, dédup auth), **sound design** (Web Audio, 13 clips). **Restent** : animations plein écran rank-up / extraction d'Ombre, onboarding complet.

## Économie — la règle à ne jamais casser
> **FAIT** (migrations `0009` + `0010`, validé par le user). SPEC §3.2 + §3.3 amendés. 227 assertions pgTAP vertes.

- **Deux pistes, et ne JAMAIS les confondre :**
  - Le **RADAR** (5 stats) = la **capacité**. XP absolue (100/250/500). Doit dépendre du volume et de la difficulté. Ne se réinitialise jamais.
  - Le **CHASSEUR** (niveau + rang) = la **discipline**. XP **normalisée** : `1000 × (XP de base ÷ dû quotidien)`. Une journée pleine vaut 1000 points **que le Chasseur ait 3 quêtes ou 10**.
- ⚠️ **Si tu casses la normalisation, tu casses le jeu** : celui qui fait 10 quêtes atteindrait Monarque en 3 mois et celui qui en fait 3 en mettrait 20. Le test `economie_test.sql` verrouille ça (3 profils, ~1000 XP chacun).
- ⚠️ **`grant_hunter_xp` prend l'XP de BASE, jamais l'XP gagnée.** Les multiplicateurs gonflent le radar, jamais le rang — sinon la promesse « Monarque à 9,5 mois » ne tient plus.
- ⚠️ **Les pénalités ne touchent jamais la piste du Chasseur** (§8). Une journée ratée ne rapporte rien ; elle ne retire rien.
- `base_xp(difficulty)` est la **source unique** de l'échelle. Ne jamais recopier `when 'easy' then 100` ailleurs (c'était le cas dans 6 fonctions).

## Décisions de game design prises (à construire plus tard)
- Reporté par le user : boss, cosmétiques, personnage, donjons. Priorité = **constance dans les habitudes + gamification**, puis **gros chantier UI/UX**, puis **muscu**. Le reste : `ROADMAP.md`.

Workflow : une branche par milestone (`m0-socle`, `m1-core-loop`…), PR à la fin, on ne commence pas le milestone suivant sans mon GO.

## État d'avancement
- **M0 → M6 : done, testés (179 assertions pgTAP vertes), et en production.** M7 : partie 1 (nav + UI) faite et déployée ; le reste est à venir.
- Critères de done validés jusqu'à M6 inclus (boss, quêtes hebdo, todos, donjon express, morning brief, Armée des Ombres, Fantôme, Journal + export image).

## Déploiement (TOUT est en ligne)
- **Supabase distant** : projet `levelup`, ref **`aqdjpadcoplcxalulllu`** (eu-west-3). Migrations **0001→0007 appliquées**, titres+items seedés (le seed ne passe pas par les migrations, l'appliquer à la main sur le distant), crons `midnight-close` + `send-notifications` (5 min) + `daily-tick` + `weekly-tick` (15 min), Edge Function `send-notifications` **v5** (T-30/T-15 + file événementielle M4). Sécurité vérifiée : seules `complete_habit` / `complete_todo` / `complete_habit_express` exécutables par `authenticated`.
- **Vercel** : prod = branche **`main`**, URL **`levelup-liart.vercel.app`** (auto-deploy au push sur `main`). Le connecteur MCP Vercel ne voit pas le projet (périmètre OAuth) → passer par `git push origin main`. Env vars (`NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`, `VAPID_PUBLIC_KEY`) réglées côté Vercel depuis M3.
- **Git** : `main` contient toute la stack M0→M7 (amenée en fast-forward). Les PR #1–#8 restent « ouvertes » (FF direct, non marquées merged sur GitHub) — cosmétique. Branche de travail courante : `m7-refonte-ui`.

## Performance — le piège à connaître
- ⚠️ **Région Vercel = région Supabase.** Par défaut Vercel exécute les fonctions à `iad1` (Washington) alors que la base est à `eu-west-3` (Paris) : chaque requête SQL devenait un aller-retour **transatlantique** (~180 ms). Le code enchaînait ~9 allers-retours en série par page → **~1,5 s de latence réseau pure**. C'était *toute* la « lag » ressentie (ni CSS, ni React). Corrigé par `vercel.json` → `"regions": ["cdg1"]` (Paris). **Vérifier après chaque déploiement** : `curl -sD- -o /dev/null <url> | grep x-vercel-id` doit contenir `cdg1`.
- `auth.getUser()` n'est **pas** gratuit : c'est un appel réseau à GoTrue qui valide le JWT. Toujours passer par `getSessionUser()` (`src/lib/auth.ts`, mémoïsé par `cache()`) dans les composants serveur — il était appelé 4× par navigation.
- `loading.tsx` est **obligatoire** : sans frontière `loading`, Next fige l'ancienne page pendant tout l'aller-retour (aucun retour visuel au tap). Contrepartie assumée : React impose un plancher d'affichage du fallback (~300 ms) avant de révéler le contenu.
- Ne pas remettre de `backdrop-filter` ni de `background-attachment: fixed` : sur un fond de dégradé lisse le flou ne change quasiment aucun pixel, mais coûte une capture plein écran par panneau, réinvalidée à chaque frame de scroll.

## Comment déployer une modif
- **Frontend/UI** : commit sur la branche de travail → `git checkout main && git merge --ff-only <branche> && git push origin main` → Vercel rebuild (~30-60 s). Vérifier via le CSS compilé en prod (`/_next/static/css/…`).
- **DB (migrations/SQL)** : ⚠️ **JAMAIS par recopie via `apply_migration`.** Faire retaper 3 000 lignes de SQL à un modèle, c'est corrompre la logique de jeu en silence (une erreur s'applique sans lever d'exception). Les migrations 0005→0007 ont ainsi perdu des commentaires en route — sans conséquence, mais c'était de la chance.
  **Méthode correcte : `psql` sur le fichier exact**, via Docker (le binaire est dans l'image Supabase) :
  ```bash
  PW=$(grep "^export SUPABASE_DB_PASSWORD=" ~/.zshrc | tail -1 | sed "s/^export SUPABASE_DB_PASSWORD=//; s/^'//; s/'$//")
  docker run --rm -i -e PGPASSWORD="$PW" public.ecr.aws/supabase/postgres:17.6.1.143 \
    psql -h aws-0-eu-west-3.pooler.supabase.com -p 5432 \
         -U postgres.aqdjpadcoplcxalulllu -d postgres \
         -v ON_ERROR_STOP=1 --single-transaction -f - < supabase/migrations/00XX_xxx.sql
  ```
  Puis enregistrer dans `supabase_migrations.schema_migrations (version, name)` (version = `date -u +%Y%m%d%H%M%S`).
  ⚠️ Le shell non-interactif ne lit **pas** `~/.zshrc` : extraire le mot de passe du fichier, ne pas compter sur `$SUPABASE_DB_PASSWORD`.
  **Vérifier après coup** : comparer l'empreinte md5 de `pg_get_functiondef()` de CHAQUE fonction, local vs prod. C'est ça qui prouve que la prod exécute le code testé.
- **Connecteur MCP `supabase-levelup`** (local, épinglé sur le projet) : pour inspecter, diagnostiquer, `get_advisors`. Pas pour écrire des migrations.
- **Vérif en conditions réelles** : signup via l'API GoTrue distante + cookie SSR (`sb-aqdjpadcoplcxalulllu-auth-token`), puis captures via Chrome headless (puppeteer-core, viewport iPhone). Nettoyer le compte de test ensuite. ⚠️ En zsh, ne jamais nommer une variable shell `UID` (lecture seule).

## Stack & conventions
- Next.js 15 App Router, TypeScript strict, Tailwind, Framer Motion
- Supabase : Postgres + Auth + Edge Functions (Deno) + pg_cron. Migrations SQL versionnées dans `supabase/migrations/`, jamais de modification de schéma hors migration.
- **Toute la logique de jeu est côté serveur** (fonctions Postgres / Edge Functions) : XP, niveaux, pénalités, streaks, boucliers, boss. Le client affiche et check-in, rien d'autre.
- RLS activé sur toutes les tables, policies testées.
- Fuseaux horaires : tout raisonne en TZ user (`profiles.timezone`), jamais en UTC naïf pour minuit/deadlines.
- Crons idempotents : `midnight-close` doit pouvoir tourner 2× sans doubler les pénalités (contraintes uniques `entity_id + date`).
- Pas de localStorage pour l'état de jeu. Web Push via lib `web-push` (VAPID), secrets dans les env vars, jamais commités.

## Tests
- Tests obligatoires sur les fonctions de jeu (pgTAP ou tests d'intégration via client Supabase) : `complete_habit`, `apply_daily_penalties` (incl. multiplicateur progressif et plancher 0), `check_streaks` (incl. boucliers), calcul de niveau/rang.
- Un milestone n'est "done" que si son critère de done (SPEC §7) est démontré + tests verts.

## Interdits
- Ne jamais faire descendre un niveau ni retirer un titre/Ombre (plancher psychologique, SPEC §8).
- Ne pas installer de lib lourde sans justification (bundle PWA).
- Ne pas générer de contenu de notification hors du seed sans me demander.

## Commandes
- `npm run dev` — dev local
- `npx supabase start` / `db reset` — Supabase local + migrations + seed
- `npm run test` — tests
- `npm run build` — vérifier avant chaque PR
