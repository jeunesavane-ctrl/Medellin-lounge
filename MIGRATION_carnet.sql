-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_carnet.sql
-- Carnet de notes rapides (ventes/dépenses hors circuit formel) —
-- intégré au système : partagé entre tous, synchronisé en temps réel.
-- Idempotent. À exécuter dans Supabase → SQL Editor → Run.
-- =====================================================================

CREATE TABLE IF NOT EXISTS carnet_entrees (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date       DATE NOT NULL,
  type       TEXT NOT NULL CHECK (type IN ('vente','depense')),
  label      TEXT,
  montant    INTEGER NOT NULL CHECK (montant > 0),
  cree_par   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_entrees DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_carnet_entrees_date ON carnet_entrees(date);
