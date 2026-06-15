-- =====================================================================
-- MEDELLIN LOUNGE — FIX_RLS.sql
-- Désactive RLS sur les 22 tables (état de démarrage prévu au CDC)
-- + (re)crée l'accès owner (PIN 1294). Idempotent.
-- À exécuter dans Supabase → SQL Editor → Run.
-- =====================================================================

ALTER TABLE config               DISABLE ROW LEVEL SECURITY;
ALTER TABLE employes             DISABLE ROW LEVEL SECURITY;
ALTER TABLE associes             DISABLE ROW LEVEL SECURITY;
ALTER TABLE produits             DISABLE ROW LEVEL SECURITY;
ALTER TABLE logs                 DISABLE ROW LEVEL SECURITY;
ALTER TABLE propositions         DISABLE ROW LEVEL SECURITY;
ALTER TABLE sessions_caisse      DISABLE ROW LEVEL SECURITY;
ALTER TABLE tables_lounge        DISABLE ROW LEVEL SECURITY;
ALTER TABLE ventes_session       DISABLE ROW LEVEL SECURITY;
ALTER TABLE verifications_staff  DISABLE ROW LEVEL SECURITY;
ALTER TABLE mouvements_caisse    DISABLE ROW LEVEL SECURITY;
ALTER TABLE achats_session       DISABLE ROW LEVEL SECURITY;
ALTER TABLE sorties_chicha       DISABLE ROW LEVEL SECURITY;
ALTER TABLE rapports             DISABLE ROW LEVEL SECURITY;
ALTER TABLE presences            DISABLE ROW LEVEL SECURITY;
ALTER TABLE justifications       DISABLE ROW LEVEL SECURITY;
ALTER TABLE avances              DISABLE ROW LEVEL SECURITY;
ALTER TABLE salaires_verses      DISABLE ROW LEVEL SECURITY;
ALTER TABLE charges              DISABLE ROW LEVEL SECURITY;
ALTER TABLE remboursements_ecart DISABLE ROW LEVEL SECURITY;
ALTER TABLE credits              DISABLE ROW LEVEL SECURITY;
ALTER TABLE votes_prop           DISABLE ROW LEVEL SECURITY;

-- (Re)bootstrap owner — PIN 1294
INSERT INTO config (key, value) VALUES
  ('pin_owner', '9c499c3ddf63c6ea23a4831f4ab64c36c8e5d64461dc4f09e12cf6d4da78ca4b'),
  ('owner_nom', 'Mohamed Lamine Savane')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
