-- =====================================================================
-- MEDELLIN LOUNGE — SCHEMA.sql
-- Système de gestion interne — Lounge Chicha & Boissons — Conakry
-- NEXUS SERVICES & CONSTRUCTION SARL — Confidentiel
-- Cahier des Charges v1.1 — Étape 0
-- =====================================================================
-- À exécuter UNE SEULE FOIS dans Supabase → SQL Editor, base VIDE.
-- Crée les 22 tables, contraintes, index. RLS désactivé (voir SECURITE.md).
-- Idempotent : CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS.
-- Noms de colonnes DÉFINITIFS : label (pas libelle), prix_defaut (pas prix),
--   stock_min (pas seuil_bas), table_label TEXT (pas table_num).
-- =====================================================================

-- ---------------------------------------------------------------------
-- BLOC 1 — Tables sans dépendance
-- ---------------------------------------------------------------------

-- 1. config (clé/valeur) — owner, PINs, paramètres généraux
CREATE TABLE IF NOT EXISTS config (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key         TEXT NOT NULL UNIQUE,
  value       TEXT,
  updated_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE config DISABLE ROW LEVEL SECURITY;

-- 2. employes (salariés uniquement — manager inclus, PAS de pourcentage)
CREATE TABLE IF NOT EXISTS employes (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nom           TEXT NOT NULL,
  prenom        TEXT,
  poste         TEXT,
  role          TEXT NOT NULL CHECK (role IN ('manager','caissier','staff','chicha','achats')),
  salaire_base  INTEGER NOT NULL DEFAULT 0,
  pin_hash      TEXT NOT NULL,
  actif         BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE employes DISABLE ROW LEVEL SECURITY;

-- 3. associes (co-investisseurs — séparés des employés, touchent des parts)
CREATE TABLE IF NOT EXISTS associes (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nom         TEXT NOT NULL,
  prenom      TEXT,
  pourcentage NUMERIC NOT NULL DEFAULT 0,
  pin_hash    TEXT NOT NULL,
  actif       BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE associes DISABLE ROW LEVEL SECURITY;

-- 4. produits (catalogue + stock ; stock jamais financier)
CREATE TABLE IF NOT EXISTS produits (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nom                 TEXT NOT NULL,
  type                TEXT NOT NULL CHECK (type IN ('chicha','boisson','autre')),
  stock_actuel        NUMERIC NOT NULL DEFAULT 0,
  stock_min           NUMERIC NOT NULL DEFAULT 0,
  prix_defaut         INTEGER NOT NULL DEFAULT 0,
  prix_achat          INTEGER NOT NULL DEFAULT 0,
  unite_vente         TEXT,
  packaging_label     TEXT,
  unite_par_packaging NUMERIC NOT NULL DEFAULT 1,
  actif               BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE produits DISABLE ROW LEVEL SECURITY;

-- 5. logs (toutes les actions via ML.logAction)
CREATE TABLE IF NOT EXISTS logs (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  role       TEXT,
  action     TEXT,
  "timestamp" TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE logs DISABLE ROW LEVEL SECURITY;

-- 6. propositions (votes entre associés)
CREATE TABLE IF NOT EXISTS propositions (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  titre       TEXT NOT NULL,
  description TEXT,
  auteur_nom  TEXT,
  statut      TEXT NOT NULL DEFAULT 'ouvert' CHECK (statut IN ('ouvert','ferme')),
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE propositions DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- BLOC 2 — Tables référençant employes
-- ---------------------------------------------------------------------

-- 7. sessions_caisse (1 session par date ; caissier_id NULL à la création)
CREATE TABLE IF NOT EXISTS sessions_caisse (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date             DATE NOT NULL UNIQUE,
  statut           TEXT NOT NULL DEFAULT 'ouvert'
                     CHECK (statut IN ('ouvert','valide_caissier','valide_manager')),
  fond_caisse      INTEGER DEFAULT 0,
  total_reel       INTEGER,
  total_om_verifie INTEGER,
  ecart_especes    INTEGER DEFAULT 0,
  ecart_om         INTEGER DEFAULT 0,
  ecart            INTEGER DEFAULT 0,
  surplus_caisse   INTEGER DEFAULT 0,
  caissier_id      UUID REFERENCES employes(id),
  note_caissier    TEXT,
  note_manager     TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sessions_caisse DISABLE ROW LEVEL SECURITY;

-- 8. tables_lounge (ouverte_par = serveuse ayant activé la table ; NULL = libre)
CREATE TABLE IF NOT EXISTS tables_lounge (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  label       TEXT NOT NULL UNIQUE,
  ordre       INTEGER NOT NULL DEFAULT 0,
  actif       BOOLEAN NOT NULL DEFAULT true,
  ouverte_par UUID REFERENCES employes(id) DEFAULT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE tables_lounge DISABLE ROW LEVEL SECURITY;
-- Renseigner les tables réelles du lounge depuis parametres.html (label + ordre).

-- ---------------------------------------------------------------------
-- BLOC 3 — Tables référençant sessions_caisse / employes / produits
-- ---------------------------------------------------------------------

-- 9. ventes_session (table_label TEXT ; crédit alimente aussi credits)
CREATE TABLE IF NOT EXISTS ventes_session (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id    UUID NOT NULL REFERENCES sessions_caisse(id),
  employe_id    UUID REFERENCES employes(id),
  produit_id    UUID REFERENCES produits(id),
  produit_nom   TEXT,
  qty           INTEGER NOT NULL DEFAULT 1,
  prix_unitaire INTEGER NOT NULL DEFAULT 0,
  total         INTEGER NOT NULL DEFAULT 0,
  paiement      TEXT NOT NULL CHECK (paiement IN ('especes','om','credit')),
  table_label   TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE ventes_session DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_ventes_table_label ON ventes_session(table_label);
CREATE INDEX IF NOT EXISTS idx_ventes_session_id  ON ventes_session(session_id);
CREATE INDEX IF NOT EXISTS idx_ventes_employe_id  ON ventes_session(employe_id);

-- 10. verifications_staff (argent réellement reçu de chaque serveuse — base écarts)
CREATE TABLE IF NOT EXISTS verifications_staff (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id   UUID NOT NULL REFERENCES sessions_caisse(id),
  employe_id   UUID NOT NULL REFERENCES employes(id),
  recu_especes INTEGER NOT NULL DEFAULT 0,
  recu_om      INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(session_id, employe_id)
);
ALTER TABLE verifications_staff DISABLE ROW LEVEL SECURITY;

-- 11. mouvements_caisse (entrées/sorties hors ventes)
CREATE TABLE IF NOT EXISTS mouvements_caisse (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES sessions_caisse(id),
  type       TEXT NOT NULL CHECK (type IN ('entree','sortie')),
  motif      TEXT,
  montant    INTEGER NOT NULL CHECK (montant > 0),
  note       TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE mouvements_caisse DISABLE ROW LEVEL SECURITY;

-- 12. achats_session (source unique des achats du jour → rapports.total_achats)
CREATE TABLE IF NOT EXISTS achats_session (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id    UUID NOT NULL REFERENCES sessions_caisse(id),
  categorie     TEXT,
  produit_nom   TEXT,
  montant       INTEGER NOT NULL CHECK (montant > 0),
  qty           NUMERIC,
  prix_unitaire INTEGER,
  created_at    TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE achats_session DISABLE ROW LEVEL SECURITY;

-- 13. sorties_chicha (STOCK uniquement — jamais financier)
CREATE TABLE IF NOT EXISTS sorties_chicha (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES sessions_caisse(id),
  employe_id UUID REFERENCES employes(id),
  arome      TEXT,
  qty        INTEGER NOT NULL DEFAULT 1,
  valide     BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sorties_chicha DISABLE ROW LEVEL SECURITY;

-- 14. rapports (1 par date ; num = MAX+1 ; recettes/net dérivés)
CREATE TABLE IF NOT EXISTS rapports (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date           DATE NOT NULL UNIQUE,
  num            INTEGER NOT NULL,
  session_id     UUID REFERENCES sessions_caisse(id),
  total_chicha   INTEGER DEFAULT 0,
  total_boissons INTEGER DEFAULT 0,
  total_achats   INTEGER DEFAULT 0,
  recettes       INTEGER DEFAULT 0,
  net            INTEGER DEFAULT 0,
  manager        TEXT,
  caissier       TEXT,
  part           JSONB,
  chicha_rows    JSONB,
  boissons_rows  JSONB,
  achats_rows    JSONB,
  created_at     TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE rapports DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- BLOC 4 — RH (référencent employes)
-- ---------------------------------------------------------------------

-- 15. presences (1 par employé/date ; 4 statuts)
CREATE TABLE IF NOT EXISTS presences (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id UUID NOT NULL REFERENCES employes(id),
  date       DATE NOT NULL,
  statut     TEXT NOT NULL CHECK (statut IN ('present','absent','retard','conge')),
  note       TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employe_id, date)
);
ALTER TABLE presences DISABLE ROW LEVEL SECURITY;

-- 16. justifications (seules absence+approuvee réduisent absNJ)
CREATE TABLE IF NOT EXISTS justifications (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id UUID NOT NULL REFERENCES employes(id),
  date       DATE,
  type       TEXT NOT NULL CHECK (type IN ('absence','retard','autre')),
  motif      TEXT,
  statut     TEXT NOT NULL DEFAULT 'en_attente'
               CHECK (statut IN ('en_attente','approuvee','rejetee')),
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE justifications DISABLE ROW LEVEL SECURITY;

-- 17. avances (déduites si approuvee AND rembourse=false — toutes dates)
CREATE TABLE IF NOT EXISTS avances (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id   UUID NOT NULL REFERENCES employes(id),
  montant      INTEGER NOT NULL CHECK (montant > 0),
  date         DATE DEFAULT CURRENT_DATE,
  statut       TEXT NOT NULL DEFAULT 'en_attente'
                 CHECK (statut IN ('en_attente','approuvee','rejetee')),
  rembourse    BOOLEAN NOT NULL DEFAULT false,
  note_demande TEXT,
  obs          TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE avances DISABLE ROW LEVEL SECURITY;

-- 18. salaires_verses (1 par employé/mois)
CREATE TABLE IF NOT EXISTS salaires_verses (
  id                       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id               UUID NOT NULL REFERENCES employes(id),
  mois                     TEXT NOT NULL,            -- YYYY-MM
  salaire_brut             INTEGER DEFAULT 0,
  avances_deduites         INTEGER DEFAULT 0,
  ecarts_deduits           INTEGER DEFAULT 0,
  surplus_caisse           INTEGER DEFAULT 0,
  net_verse                INTEGER DEFAULT 0,
  nb_absences_nj           INTEGER DEFAULT 0,
  sanction_type            TEXT,
  sanction_montant         INTEGER DEFAULT 0,
  nb_retards               INTEGER DEFAULT 0,
  sanction_retard_montant  INTEGER DEFAULT 0,
  paye_le                  DATE,
  created_at               TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employe_id, mois)
);
ALTER TABLE salaires_verses DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- BLOC 5 — Charges, écarts, crédits, votes
-- ---------------------------------------------------------------------

-- 19. charges (label PAS libelle ; JAMAIS de salaire)
CREATE TABLE IF NOT EXISTS charges (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  label         TEXT NOT NULL,
  montant       INTEGER NOT NULL CHECK (montant > 0),
  mois          TEXT,                    -- YYYY-MM
  categorie     TEXT,
  paye          BOOLEAN NOT NULL DEFAULT false,
  date_paiement DATE,
  recurrence    TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE charges DISABLE ROW LEVEL SECURITY;

-- 20. remboursements_ecart (badge nav caisse quand en_attente)
CREATE TABLE IF NOT EXISTS remboursements_ecart (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id UUID REFERENCES sessions_caisse(id),
  employe_id UUID NOT NULL REFERENCES employes(id),
  montant    INTEGER NOT NULL CHECK (montant > 0),
  note       TEXT,
  statut     TEXT NOT NULL DEFAULT 'en_attente'
               CHECK (statut IN ('en_attente','valide','rejete')),
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE remboursements_ecart DISABLE ROW LEVEL SECURITY;

-- 21. credits (ardoises clients — 1 par vente paiement=credit)
CREATE TABLE IF NOT EXISTS credits (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id UUID REFERENCES employes(id),
  session_id UUID REFERENCES sessions_caisse(id),
  montant    INTEGER NOT NULL CHECK (montant > 0),
  rembourse  BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE credits DISABLE ROW LEVEL SECURITY;

-- 22. votes_prop (votant_key = associe.id::text OU 'owner' ; vote pondéré)
CREATE TABLE IF NOT EXISTS votes_prop (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  proposition_id UUID NOT NULL REFERENCES propositions(id),
  votant_key     TEXT NOT NULL,
  votant_nom     TEXT,
  poids          NUMERIC DEFAULT 0,
  choix          BOOLEAN,
  created_at     TIMESTAMPTZ DEFAULT now(),
  UNIQUE(proposition_id, votant_key)
);
ALTER TABLE votes_prop DISABLE ROW LEVEL SECURITY;

-- 23. bons_chicha (lien caissière → chichamen ; le stock bouge à la validation, pas à la vente)
--     vente_id renseigné quand le bon vient de la validation d'une vente serveuse (sinon créé
--     directement par la caissière, vente_id NULL)
CREATE TABLE IF NOT EXISTS bons_chicha (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id   UUID NOT NULL REFERENCES sessions_caisse(id),
  produit_id   UUID REFERENCES produits(id),
  produit_nom  TEXT,
  vente_id     UUID REFERENCES ventes_session(id),
  arome        TEXT,
  qty          INTEGER NOT NULL DEFAULT 1,
  demande_par  TEXT,
  statut       TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','servi','annule')),
  cree_par     UUID REFERENCES employes(id),
  servi_par    UUID REFERENCES employes(id),
  servi_le     TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE bons_chicha DISABLE ROW LEVEL SECURITY;

-- =====================================================================
-- FIN — 23 tables créées.
-- Étape suivante (1) : shared.js + shared.css.
-- Bootstrap auth : insérer pin_owner / owner_nom dans config avant
--   le premier login (sera fait via parametres.html ou seed manuel).
-- =====================================================================
