-- =============================================================
-- LEVELUP — Seed catalogue titres & items (M4)
-- Fichier : supabase/seed/titles_items_seed.sql
-- Titres : paliers de streak global (§3.4) + récompense de boss (§3.7).
-- Items  : catalogue minimal, noms/icônes PLACEHOLDER (à remplacer par du
-- vrai contenu design plus tard, comme les icônes PWA de M0) — juste assez
-- pour que les récompenses (boss, coffre, quête secrète) fonctionnent.
-- =============================================================

insert into titles (name, condition) values
  ('Éveillé', '{"type":"streak_global","days":7}'::jsonb),
  ('Régulier', '{"type":"streak_global","days":21}'::jsonb),
  ('Discipline de Fer', '{"type":"streak_global","days":42}'::jsonb),
  ('Inarrêtable', '{"type":"streak_global","days":66}'::jsonb),
  ('Monarque', '{"type":"streak_global","days":100}'::jsonb),
  ('Tueur de Boss', '{"type":"boss_defeat"}'::jsonb)
on conflict (name) do nothing;

insert into items (name, type, rarity, icon, effect) values
  ('Écusson du Chasseur', 'badge', 'common', 'badge-hunter', '{}'::jsonb),
  ('Fragment d''Ombre', 'skin', 'common', 'skin-shadow-fragment', '{}'::jsonb),
  ('Sceau de Discipline', 'badge', 'common', 'badge-discipline', '{}'::jsonb),
  ('Relique du Vainqueur', 'badge', 'rare', 'badge-victor', '{}'::jsonb),
  ('Emblème du Rang S', 'skin', 'rare', 'skin-rank-s', '{}'::jsonb);
