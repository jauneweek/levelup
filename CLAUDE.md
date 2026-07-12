# CLAUDE.md — LEVELUP (Habit Tracker RPG)

## Contexte
Habit tracker gamifié style Solo Leveling. PWA Next.js + Supabase + Vercel. Zéro IA en V1 (moteur de règles + templates).

## Source de vérité
- **Lis `SPEC.md` avant toute tâche.** Toutes les formules (XP, niveaux, pénalités, streaks), le schéma de données, les mécaniques et la roadmap y sont verrouillés. Ne modifie JAMAIS une formule ou une règle de jeu sans me demander.
- Seed des notifications : `supabase/seed/notification_templates.sql` (ne pas réécrire les templates).
- DA : `SPEC.md §9` (tokens, composant Fenêtre Système, grammaire des couleurs) + mockups de référence dans `design/mockups/`. Utilise la skill frontend-design. Jamais de Tailwind générique : hexagones, corner brackets, glow violet.

## Milestone en cours
> **M7 — Polish** (en cours : refonte navigation 4 onglets + UI collée aux mockups. Restent : animations rank-up/extraction plein écran, onboarding complet, sons.)

Workflow : une branche par milestone (`m0-socle`, `m1-core-loop`…), PR à la fin, on ne commence pas le milestone suivant sans mon GO.

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
