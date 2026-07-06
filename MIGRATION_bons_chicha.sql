-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_bons_chicha.sql
-- Ajoute le lien caissière ↔ chichamen : la caissière crée un "bon"
-- (produit = l'arôme lui-même : Love/Café/Gibiar/Hawai, quantité,
-- table/demandeur), le chichaman le voit en temps réel et le valide
-- quand c'est prêt — c'est CE moment qui décrémente le stock (plus au
-- moment de la vente, pour éviter le double décompte). Idempotent.
-- À exécuter dans Supabase → SQL Editor → Run.
-- =====================================================================

CREATE TABLE IF NOT EXISTS bons_chicha (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id   UUID NOT NULL REFERENCES sessions_caisse(id),
  produit_id   UUID REFERENCES produits(id),         -- l'arôme est le produit (Love, Café, Gibiar, Hawai)
  produit_nom  TEXT,
  vente_id     UUID REFERENCES ventes_session(id),  -- rempli quand le bon vient de la validation d'une vente serveuse
  qty          INTEGER NOT NULL DEFAULT 1,
  demande_par  TEXT,                 -- ex : "Table 4", "Fatoumata", "Comptoir" — texte libre saisi par la caissière
  statut       TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','servi','annule')),
  cree_par     UUID REFERENCES employes(id),
  servi_par    UUID REFERENCES employes(id),
  servi_le     TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE bons_chicha DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_bons_chicha_session  ON bons_chicha(session_id);
CREATE INDEX IF NOT EXISTS idx_bons_chicha_statut   ON bons_chicha(statut);
CREATE INDEX IF NOT EXISTS idx_bons_chicha_vente_id ON bons_chicha(vente_id);

-- sorties_chicha : mémoriser QUEL produit (arôme) est sorti.
-- Sans ça, l'annulation d'une sortie restaurait le stock du mauvais produit
-- (le premier alphabétique) — critique depuis que chaque arôme est un produit.
ALTER TABLE sorties_chicha ADD COLUMN IF NOT EXISTS produit_id UUID REFERENCES produits(id);
