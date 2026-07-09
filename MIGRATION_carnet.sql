-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_carnet.sql (v2 — carnet complet)
-- Carnet de gestion quotidien, partagé et temps réel :
--   · ventes par catégorie (chicha/boissons/autre) et paiement (esp/OM/crédit)
--   · dépenses par nature (achats/salaire/charge/divers)
--   · fond de caisse + note du jour
-- Idempotent. À exécuter dans Supabase → SQL Editor → Run
-- (coller dans une requête VIDE, sans texte surligné).
-- =====================================================================

CREATE TABLE IF NOT EXISTS carnet_entrees (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date       DATE NOT NULL,
  type       TEXT NOT NULL CHECK (type IN ('vente','depense')),
  categorie  TEXT,                -- vente : chicha|boissons|autre · dépense : achats|salaire|charge|divers
  label      TEXT,
  montant    INTEGER NOT NULL CHECK (montant > 0),
  paiement   TEXT,                -- ventes uniquement : especes|om|credit
  cree_par   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_entrees DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_carnet_entrees_date ON carnet_entrees(date);

-- Si une version antérieure de la table existait déjà, compléter les colonnes
ALTER TABLE carnet_entrees ADD COLUMN IF NOT EXISTS categorie TEXT;
ALTER TABLE carnet_entrees ADD COLUMN IF NOT EXISTS paiement  TEXT;

-- Métadonnées du jour : fond de caisse et note libre (1 ligne par date)
CREATE TABLE IF NOT EXISTS carnet_jours (
  date        DATE PRIMARY KEY,
  fond_caisse INTEGER DEFAULT 0,
  note        TEXT,
  maj_par     TEXT,
  updated_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_jours DISABLE ROW LEVEL SECURITY;
