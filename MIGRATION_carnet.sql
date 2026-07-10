-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_carnet.sql (v4 — totaux jour + stock avant/après)
-- Carnet de gestion quotidien, partagé et temps réel :
--   · ventes = 2 totaux par jour (Chicha, Boissons) — PAS par transaction
--   · dépenses par nature, restent itemisées (achats/salaire/charge/divers)
--   · fond de caisse + note du jour
--   · stock = comptage avant/après soirée par produit (écart = consommé)
-- Idempotent. À exécuter dans Supabase → SQL Editor → Run
-- (coller dans une requête VIDE, sans texte surligné).
-- =====================================================================

CREATE TABLE IF NOT EXISTS carnet_entrees (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date       DATE NOT NULL,
  type       TEXT NOT NULL CHECK (type IN ('vente','depense')),
  categorie  TEXT,                -- dépense : achats|salaire|charge|divers
  label      TEXT,
  montant    INTEGER NOT NULL CHECK (montant > 0),
  paiement   TEXT,
  cree_par   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_entrees DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_carnet_entrees_date ON carnet_entrees(date);
ALTER TABLE carnet_entrees ADD COLUMN IF NOT EXISTS categorie TEXT;
ALTER TABLE carnet_entrees ADD COLUMN IF NOT EXISTS paiement  TEXT;

-- Métadonnées + totaux du jour (1 ligne par date)
CREATE TABLE IF NOT EXISTS carnet_jours (
  date           DATE PRIMARY KEY,
  total_chicha   INTEGER DEFAULT 0,
  total_boissons INTEGER DEFAULT 0,
  fond_caisse    INTEGER DEFAULT 0,
  note           TEXT,
  maj_par        TEXT,
  updated_at     TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_jours DISABLE ROW LEVEL SECURITY;
ALTER TABLE carnet_jours ADD COLUMN IF NOT EXISTS total_chicha   INTEGER DEFAULT 0;
ALTER TABLE carnet_jours ADD COLUMN IF NOT EXISTS total_boissons INTEGER DEFAULT 0;

-- Report ponctuel : les ventes déjà saisies en détail (ancien modèle par
-- transaction) sont reportées dans les totaux du jour (nouveau modèle).
-- Sans effet si aucune vente n'a encore été saisie. À ne lancer qu'une fois.
INSERT INTO carnet_jours (date, total_chicha, total_boissons, maj_par)
SELECT
  date,
  COALESCE(SUM(montant) FILTER (WHERE categorie = 'chicha'), 0),
  COALESCE(SUM(montant) FILTER (WHERE categorie IS DISTINCT FROM 'chicha'), 0),
  'migration'
FROM carnet_entrees
WHERE type = 'vente'
GROUP BY date
ON CONFLICT (date) DO UPDATE SET
  total_chicha   = carnet_jours.total_chicha   + EXCLUDED.total_chicha,
  total_boissons = carnet_jours.total_boissons + EXCLUDED.total_boissons;

-- Stock : comptage avant / après soirée par produit et par jour.
-- L'écart (avant − après) = ce qui est parti ce jour-là.
CREATE TABLE IF NOT EXISTS carnet_stock (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date       DATE NOT NULL,
  produit    TEXT NOT NULL,
  avant      INTEGER,
  apres      INTEGER,
  cree_par   TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(date, produit)
);
ALTER TABLE carnet_stock DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_carnet_stock_date ON carnet_stock(date);
