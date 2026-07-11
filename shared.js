// =====================================================================
// MEDELLIN LOUNGE — shared.js
// Fondation : Supabase · auth/session · navigation · utils · sécurité XSS
// Cahier des Charges v1.1 — Étape 1
// Charger APRÈS le script supabase-js, AVANT le script de la page.
// =====================================================================

// --- Connexion Supabase -------------------------------------------------
const SUPABASE_URL = "https://xkdlkvwtzfixsaiexdkf.supabase.co";
const SUPABASE_KEY = "sb_publishable_w_H1JOlysnd1KFIs3bmQlg_KMbsyc44";
const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// --- Police d'icônes (Tabler) -------------------------------------------
(function loadIcons() {
  if (document.getElementById("ml-ti")) return;
  const l = document.createElement("link");
  l.id = "ml-ti"; l.rel = "stylesheet";
  l.href = "https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@3/dist/tabler-icons.min.css";
  document.head.appendChild(l);
})();

// --- Raccourci DOM ------------------------------------------------------
const $ = (id) => document.getElementById(id);

// =====================================================================
// SÉCURITÉ — Anti-XSS (OBLIGATOIRE, sans exception)
// =====================================================================
function escHtml(s) {
  if (s === null || s === undefined) return "";
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
function jsStr(s) {
  if (s === null || s === undefined) return "";
  return String(s)
    .replaceAll("\\", "\\\\")
    .replaceAll("'", "\\'")
    .replaceAll('"', '\\"')
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r");
}

// =====================================================================
// HASH — SHA-256 hex (identique au flux d'auth)
// =====================================================================
async function sha256(str) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// =====================================================================
// FORMATAGE — montants & dates (fr)
// =====================================================================
function gnf(n) {
  const v = Math.round(Number(n) || 0);
  return v.toLocaleString("fr-FR").replace(/\s/g, " ") + " GNF";
}
function _toDate(d) {
  if (d instanceof Date) return d;
  if (typeof d === "string" && d.length === 10) return new Date(d + "T00:00:00");
  return new Date(d);
}
function frDate(d) {
  return _toDate(d).toLocaleDateString("fr-FR", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  });
}
function frDateShort(d) {
  return _toDate(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long" });
}
function frMonth(d) {
  return _toDate(d).toLocaleDateString("fr-FR", { month: "long", year: "numeric" });
}
function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate()
  ).padStart(2, "0")}`;
}

// =====================================================================
// TOAST — notification (type = "" | "ok" | "ko")
// =====================================================================
let _toastTimer;
function toast(msg, type = "") {
  const el = $("toast");
  if (!el) { alert(msg); return; }
  el.textContent = msg;
  el.className = "show" + (type ? " " + type : "");
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => { el.className = ""; }, 3200);
}

// =====================================================================
// SESSION & AUTH — ML.*
// sessionStorage : ml_role · ml_extra · ml_hashes {hOwner,hManager}
// =====================================================================
const ML = {
  getRole() {
    return sessionStorage.getItem("ml_role") || null;
  },
  getExtra() {
    try { return JSON.parse(sessionStorage.getItem("ml_extra") || "{}"); }
    catch { return {}; }
  },
  getHashes() {
    try { return JSON.parse(sessionStorage.getItem("ml_hashes") || "{}"); }
    catch { return {}; }
  },
  setSession(role, extra, hashes) {
    sessionStorage.setItem("ml_role", role);
    sessionStorage.setItem("ml_extra", JSON.stringify(extra || {}));
    if (hashes) sessionStorage.setItem("ml_hashes", JSON.stringify(hashes));
  },
  guard(roles) {
    const r = this.getRole();
    if (!r || (Array.isArray(roles) && roles.length && !roles.includes(r))) {
      location.href = "index.html";
      return false;
    }
    return true;
  },
  lock() {
    sessionStorage.clear();
    location.href = "index.html";
  },
  async logAction(desc) {
    try { await db.from("logs").insert({ role: this.getRole(), action: desc }); }
    catch (e) { /* log silencieux */ }
  },
  initAutoLock() {
    let t;
    const reset = () => {
      clearTimeout(t);
      t = setTimeout(() => ML.lock(), 10 * 60 * 1000); // 10 min
    };
    ["click", "keydown", "touchstart", "mousemove"].forEach((ev) =>
      document.addEventListener(ev, reset, { passive: true })
    );
    reset();
  },
  toggleNav() {
    const sb = $("ml-sidebar"), ov = $("ml-overlay");
    const open = sb && !sb.classList.contains("open");
    sb?.classList.toggle("open", open);
    ov?.classList.toggle("open", open);
  },
};

// =====================================================================
// STOCK — helper mouvement (enregistre chaque entrée/sortie/ajustement)
// =====================================================================
async function stockMvt(produit_id, qty, source, note, ref_id) {
  if (!produit_id) return;
  try {
    await db.from("mouvements_stock").insert({
      produit_id, qty,
      type: qty > 0 ? "entree" : qty < 0 ? "sortie" : "ajustement",
      source, note: note || null, reference_id: ref_id || null,
      employe_id: ML.getExtra()?.employe_id || null,
    });
  } catch(e) { console.error("stockMvt:", e); }
}

// =====================================================================
// SUPPRESSION — cascade complète d'une session (ordre enfants → parent)
// Toutes les tables liées à une session_caisse sont couvertes ici pour
// éviter qu'un oubli bloque la suppression finale (violation de clé).
// =====================================================================
async function wipeSessionCascade(sid, { restoreStock = true } = {}) {
  if (!sid) return;
  // 1. Remettre en stock ce qui avait été vendu (annulation d'un jour)
  if (restoreStock) {
    const { data: ventes } = await db.from("ventes_session").select("produit_id,qty").eq("session_id", sid);
    const map = {};
    (ventes || []).forEach(v => { if (v.produit_id) map[v.produit_id] = (map[v.produit_id] || 0) + (v.qty || 0); });
    for (const [pid, qty] of Object.entries(map)) {
      const { data: p } = await db.from("produits").select("stock_actuel").eq("id", pid).maybeSingle();
      if (p) await db.from("produits").update({ stock_actuel: (p.stock_actuel || 0) + qty }).eq("id", pid);
    }
  }
  // 2. Enfants d'abord (chaque delete isolé : une table absente ne bloque pas)
  const del = (t, col) => db.from(t).delete().eq(col, sid).then(r => r, () => ({}));
  await del("bons_chicha", "session_id");
  await Promise.all([
    del("ventes_session", "session_id"),
    del("verifications_staff", "session_id"),
    del("mouvements_caisse", "session_id"),
    del("achats_session", "session_id"),
    del("sorties_chicha", "session_id"),
    del("credits", "session_id"),
    del("remboursements_ecart", "session_id"),
    del("rapports", "session_id"),
    del("sessions_serveuse", "session_caisse_id"),
  ]);
  // 3. La session elle-même en dernier
  await db.from("sessions_caisse").delete().eq("id", sid);
}

// =====================================================================
// RÉINITIALISATION — efface TOUTES les ventes / rapports du système.
// Ne touche PAS : produits/stock, employés, associés, charges, RH, config.
// Owner uniquement. Ordre enfants → parents pour respecter les clés.
// =====================================================================
async function wipeAllSalesData() {
  const NONE = "00000000-0000-0000-0000-000000000000";
  const wipe = (t) => db.from(t).delete().neq("id", NONE).then(r => r, () => ({}));
  await wipe("bons_chicha");
  await Promise.all([
    wipe("ventes_session"),
    wipe("verifications_staff"),
    wipe("mouvements_caisse"),
    wipe("achats_session"),
    wipe("sorties_chicha"),
    wipe("credits"),
    wipe("remboursements_ecart"),
    wipe("rapports"),
    wipe("sessions_serveuse"),
  ]);
  await wipe("sessions_caisse");
  // Libère toutes les tables physiques (aucune session active)
  await db.from("tables_lounge").update({ ouverte_par: null }).not("ouverte_par", "is", null);
}

// =====================================================================
// NAVIGATION — 18 pages, filtrées par rôle (CDC §3)
// =====================================================================
const ROLE_LABEL = { owner: "Gestionnaire", manager: "Manager", caissier: "Caissier", staff: "Serveuse", chicha: "Chicha", achats: "Achats", associe: "Associé" };

const NAV = [
  { href: "dashboard.html",  label: "Tableau de bord", icon: "ti-layout-dashboard", roles: ["manager", "owner", "associe"], group: "Service" },
  { href: "saisie.html",     label: "Ventes",          icon: "ti-shopping-cart",    roles: ["staff"], group: "Service" },
  { href: "caisse.html",     label: "Caisse",          icon: "ti-cash",             roles: ["caissier", "manager", "owner", "associe"], badge: "nbadge-caisse", group: "Service" },
  { href: "chicha.html",     label: "Chicha",          icon: "ti-flame",            roles: ["chicha", "manager", "owner"], badge: "nbadge-chicha", group: "Service" },
  { href: "achats.html",     label: "Achats",          icon: "ti-shopping-bag",     roles: ["achats", "manager", "owner"], group: "Service" },
  { href: "rapport.html",    label: "Rapport",         icon: "ti-file-text",        roles: ["manager", "owner"], group: "Gestion" },
  { href: "historique.html", label: "Historique",      icon: "ti-history",          roles: ["manager", "owner"], group: "Gestion" },
  { href: "carnet.html",     label: "Carnet",          icon: "ti-notebook",         roles: ["owner"], group: "Gestion" },
  { href: "stock.html",      label: "Stock",           icon: "ti-package",          roles: ["manager", "owner"], group: "Gestion" },
  { href: "produits.html",   label: "Produits",        icon: "ti-box",              roles: ["manager", "owner"], group: "Gestion" },
  { href: "charges.html",    label: "Charges",         icon: "ti-receipt",          roles: ["manager", "owner"], group: "Gestion" },
  { href: "rh.html",         label: "RH",              icon: "ti-users",            roles: ["manager", "owner"], group: "Équipe" },
  { href: "pointage.html",   label: "Présences",       icon: "ti-calendar",         roles: ["manager", "owner"], group: "Équipe" },
  { href: "avances.html",    label: "Avances",         icon: "ti-wallet",           roles: ["manager", "owner"], badge: "nbadge-avances", group: "Équipe" },
  { href: "finances.html",   label: "Finances",        icon: "ti-chart-line",       roles: ["owner", "manager", "associe"], group: "Direction" },
  { href: "bilan.html",      label: "Bilan",           icon: "ti-report-money",     roles: ["owner", "manager", "associe"], group: "Direction" },
  { href: "associes.html",   label: "Associés",        icon: "ti-users-group",      roles: ["owner", "associe"], group: "Direction" },
  { href: "parametres.html", label: "Paramètres",      icon: "ti-settings",         roles: ["owner"], group: "Direction" },
  { href: "fiche.html",      label: "Ma fiche",        icon: "ti-id-badge-2",       roles: ["staff", "caissier", "chicha", "achats", "manager"], group: "Moi" },
  { href: "avance.html",     label: "Demande avance",  icon: "ti-cash-banknote",    roles: ["staff", "caissier", "chicha", "achats", "manager"], group: "Moi" },
];

function renderNav() {
  const nav = $("ml-nav");
  if (!nav) return;
  const role = ML.getRole();
  const extra = ML.getExtra();
  const current = location.pathname.split("/").pop() || "index.html";
  const visible = NAV.filter((i) => i.roles.includes(role));
  const nbGroups = new Set(visible.map((i) => i.group)).size;
  let html = "", lastGroup = null;
  for (const item of visible) {
    if (nbGroups > 1 && item.group !== lastGroup) {
      html += `<div class="ml-group">${escHtml(item.group)}</div>`;
      lastGroup = item.group;
    }
    const active = item.href === current ? " active" : "";
    const badge = item.badge ? `<span class="ml-badge" id="${item.badge}" hidden></span>` : "";
    html += `<a href="${item.href}" class="ml-link${active}">
      <i class="ti ${item.icon || "ti-point"}" aria-hidden="true"></i>
      <span class="ml-label">${escHtml(item.label)}</span>${badge}</a>`;
  }
  nav.innerHTML = html;

  const box = $("ml-userbox");
  if (box) {
    const nom = extra.nom || role || "";
    const initiales = nom.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase() || "?";
    box.innerHTML = `
      <div class="ml-avatar">${escHtml(initiales)}</div>
      <div class="ml-user-meta">
        <b>${escHtml(nom)}</b>
        <span>${escHtml(ROLE_LABEL[role] || role || "")}</span>
      </div>
      <button class="ml-logout" onclick="ML.lock()" aria-label="Déconnexion" title="Déconnexion"><i class="ti ti-logout"></i></button>`;
  }
}

// --- Badges rouges (remboursements + avances) --------------------------
function _setBadge(id, count) {
  const el = $(id);
  if (!el) return;
  if (count && count > 0) { el.textContent = count; el.hidden = false; }
  else { el.hidden = true; }
}
async function loadNavBadges() {
  const role = ML.getRole();
  try {
    if (["caissier", "manager", "owner"].includes(role)) {
      const { count } = await db
        .from("remboursements_ecart")
        .select("id", { count: "exact", head: true })
        .eq("statut", "en_attente");
      _setBadge("nbadge-caisse", count);
    }
    if (["manager", "owner"].includes(role)) {
      const { count } = await db
        .from("avances")
        .select("id", { count: "exact", head: true })
        .eq("statut", "en_attente");
      _setBadge("nbadge-avances", count);
    }
    if (["chicha", "manager", "owner"].includes(role)) {
      const { count } = await db
        .from("bons_chicha")
        .select("id", { count: "exact", head: true })
        .eq("statut", "en_attente");
      _setBadge("nbadge-chicha", count);
    }
  } catch (e) { /* badges non bloquants */ }
}

// =====================================================================
// INIT — à appeler au début de chaque page protégée
// guard + renderNav + initAutoLock + loadNavBadges
// =====================================================================
function initPage(roles) {
  if (!ML.guard(roles)) return false;
  renderNav();
  ML.initAutoLock();
  loadNavBadges();
  return true;
}

// =====================================================================
// HEADER — injecté dans chaque page via insertAdjacentHTML("afterbegin")
// =====================================================================
const HEADER_HTML = `
<div class="ml-topbar">
  <button class="ml-burger" onclick="ML.toggleNav()" aria-label="Menu"><i class="ti ti-menu-2"></i></button>
  <span class="ml-topbrand">Medellin <span>Lounge</span></span>
</div>
<div class="ml-overlay" id="ml-overlay" onclick="ML.toggleNav()"></div>
<aside class="ml-sidebar" id="ml-sidebar">
  <div class="ml-brand">
    <div class="ml-logo">ML</div>
    <div class="ml-brandtext"><b>Medellin Lounge</b><small>CONAKRY</small></div>
  </div>
  <nav id="ml-nav" class="ml-nav"></nav>
  <div class="ml-side-foot"><div class="ml-user" id="ml-userbox"></div></div>
</aside>`;

// --- Onde au clic sur les boutons (purement visuel) ---------------------
document.addEventListener("click", (e) => {
  const el = e.target.closest(".btn");
  if (!el || el.disabled) return;
  const rect = el.getBoundingClientRect();
  const size = Math.max(rect.width, rect.height);
  const r = document.createElement("span");
  r.className = "ripple";
  r.style.width = r.style.height = size + "px";
  r.style.left = (e.clientX - rect.left - size / 2) + "px";
  r.style.top = (e.clientY - rect.top - size / 2) + "px";
  el.appendChild(r);
  setTimeout(() => r.remove(), 600);
}, true);
