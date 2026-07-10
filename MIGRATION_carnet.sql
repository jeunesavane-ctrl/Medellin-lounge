-- =====================================================================
-- MEDELLIN LOUNGE — MIGRATION_carnet.sql (v5 — totaux jour + stock avant/après + catalogue produits)
-- Carnet de gestion quotidien, partagé et temps réel :
--   · ventes = 2 totaux par jour (Chicha, Boissons) — PAS par transaction
--   · chicha = nombre vendu × prix fixe (catalogue)
--   · dépenses par nature, restent itemisées (achats/salaire/charge/divers)
--   · fond de caisse + note du jour
--   · stock boissons = comptage avant/après soirée par produit (écart = consommé)
--   · catalogue produits (nom, type, prix) — propre au carnet, sans lien avec
--     le catalogue du vrai système (évite de modifier des prix utilisés en caisse)
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
  chicha_qty     INTEGER DEFAULT 0,   -- nombre de chichas vendus (total_chicha = chicha_qty × prix au moment de la saisie)
  fond_caisse    INTEGER DEFAULT 0,
  note           TEXT,
  maj_par        TEXT,
  updated_at     TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_jours DISABLE ROW LEVEL SECURITY;
ALTER TABLE carnet_jours ADD COLUMN IF NOT EXISTS total_chicha   INTEGER DEFAULT 0;
ALTER TABLE carnet_jours ADD COLUMN IF NOT EXISTS total_boissons INTEGER DEFAULT 0;
ALTER TABLE carnet_jours ADD COLUMN IF NOT EXISTS chicha_qty     INTEGER DEFAULT 0;

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

-- Stock boissons : comptage avant / après soirée par produit et par jour.
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

-- Catalogue produits & prix (propre au carnet — n'affecte jamais les prix
-- utilisés en caisse par le vrai système). "Chicha" = prix fixe.
CREATE TABLE IF NOT EXISTS carnet_produits (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nom        TEXT NOT NULL UNIQUE,
  type       TEXT NOT NULL CHECK (type IN ('chicha','boisson')),
  prix       INTEGER NOT NULL CHECK (prix > 0),
  actif      BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE carnet_produits DISABLE ROW LEVEL SECURITY;

INSERT INTO carnet_produits (nom, type, prix) VALUES
  ('Chicha',        'chicha',  70000),
  ('Coca Cola',     'boisson', 15000),
  ('Fanta',         'boisson', 15000),
  ('Lait',          'boisson', 25000),
  ('Eau',           'boisson',  5000),
  ('XXL',           'boisson', 15000),
  ('Vimto',         'boisson', 20000),
  ('Vody',          'boisson', 20000),
  ('Sprite',        'boisson', 15000),
  ('Jus de fruit',  'boisson', 15000),
  ('Guinness',      'boisson', 20000),
  ('33 Export',     'boisson', 15000)
ON CONFLICT (nom) DO NOTHING;
