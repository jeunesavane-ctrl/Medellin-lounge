-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_bons_chicha.sql
-- Ajoute le lien caissière ↔ chichamen : la caissière crée un "bon"
-- (produit, arôme, quantité, table/demandeur), le chichaman le voit
-- en temps réel et le valide quand c'est prêt — c'est CE moment qui
-- décrémente le stock (plus au moment de la vente, pour éviter le
-- double décompte). Idempotent.
-- À exécuter dans Supabase → SQL Editor → Run.
-- =====================================================================

CREATE TABLE IF NOT EXISTS bons_chicha (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id   UUID NOT NULL REFERENCES sessions_caisse(id),
  produit_id   UUID REFERENCES produits(id),
  produit_nom  TEXT,
  arome        TEXT,
  qty          INTEGER NOT NULL DEFAULT 1,
  demande_par  TEXT,                 -- ex : "Table 4", "Fatoumata", "Comptoir" — texte libre saisi par la caissière
  statut       TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','servi','annule')),
  cree_par     UUID REFERENCES employes(id),
  servi_par    UUID REFERENCES employes(id),
  servi_le     TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE bons_chicha DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_bons_chicha_session ON bons_chicha(session_id);
CREATE INDEX IF NOT EXISTS idx_bons_chicha_statut  ON bons_chicha(statut);
