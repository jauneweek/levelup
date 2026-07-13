-- ============================================================================
-- Le rang terminal : Monarque.
--
-- Fichier séparé À DESSEIN. Postgres interdit d'UTILISER une valeur d'enum dans
-- la transaction qui l'ajoute — or la migration suivante en a besoin dès la
-- création de `rank_for_hunter_level()`. Deux migrations = deux transactions.
-- ============================================================================

alter type hunter_rank add value if not exists 'M';
