import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

// Bump alongside sw.js's CACHE constant on every push to GitHub.
const APP_VERSION = 'v1.28';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
document.getElementById('appVersion').textContent = APP_VERSION;

// ── State ──────────────────────────────────────────────────────
let currentUser  = null;
let currentRole  = 'operator';
let currentUserName = '';
let currentOrg   = null;
let profileMap   = {};
let logs         = [];
let fields       = [];
let pendingDeleteId   = null;
let viewMode     = 'compact';
let currentMonth = new Date().toISOString().slice(0, 7);

let currentTab       = 'nalogi'; // 'evidenca' | 'nalogi'
let workOrders       = [];
let workOrdersLoaded = false;
let workOrderCenterPoints = {}; // work_order_id -> {lat, lng}, from get_work_orders_center_points
let customers        = [];
let operatorsList    = [];

// ── DOM refs ───────────────────────────────────────────────────
const operatorNameEl = document.getElementById('operatorName');
const greetingEl     = document.getElementById('greeting');
const todayDateEl    = document.getElementById('todayDate');
const logoutBtn      = document.getElementById('logoutBtn');
const addBtn         = document.getElementById('addBtn');
const logsList       = document.getElementById('logsList');
const viewCardsBtn   = document.getElementById('viewCardsBtn');
const viewListBtn    = document.getElementById('viewListBtn');

const statTotal  = document.getElementById('statTotal');
const statWork   = document.getElementById('statWork');
const statRoad   = document.getElementById('statRoad');
const statGerk   = document.getElementById('statGerk');
const adminBadge = document.getElementById('adminBadge');

const monthLabel   = document.getElementById('monthLabel');
const prevMonthBtn = document.getElementById('prevMonthBtn');
const nextMonthBtn = document.getElementById('nextMonthBtn');

const formModal   = document.getElementById('formModal');
const modalTitle  = document.getElementById('modalTitle');
const modalClose  = document.getElementById('modalClose');
const workLogForm = document.getElementById('workLogForm');
const workLogOrderLabel = document.getElementById('workLogOrderLabel');
const workLogDateInput = document.getElementById('workLogDate');
const woStartBtn  = document.getElementById('woStartBtn');
const woMapsLink  = document.getElementById('woMapsLink');
const woHeaderMeta = document.getElementById('woHeaderMeta');
const roadTypeSel = document.getElementById('roadType');
const roadHourSel = document.getElementById('roadHour');
const roadMinSel  = document.getElementById('roadMin');
const roadAddBtn  = document.getElementById('roadAddBtn');
const roadTimeListEl = document.getElementById('roadTimeList');
const workLogGerkRowsEl = document.getElementById('workLogGerkRows');
const tractorInput = document.getElementById('tractor');
const descInput   = document.getElementById('description');
const formError   = document.getElementById('formError');
const formSuccess = document.getElementById('formSuccess');
const cancelBtn   = document.getElementById('cancelBtn');

const deleteModal      = document.getElementById('deleteModal');
const deleteCancelBtn  = document.getElementById('deleteCancelBtn');
const deleteConfirmBtn = document.getElementById('deleteConfirmBtn');

// ── Tabs ───────────────────────────────────────────────────────
const tabEvidenca   = document.getElementById('tabEvidenca');
const tabNalogi     = document.getElementById('tabNalogi');
const panelEvidenca = document.getElementById('panelEvidenca');
const panelNalogi   = document.getElementById('panelNalogi');
const workOrdersList = document.getElementById('workOrdersList');
const woSearchStranka = document.getElementById('woSearchStranka');
const woSearchSuggestions = document.getElementById('woSearchSuggestions');

// ── Seznam strank / Deklaracije modal refs (admin only) ──────────
const fabMenu               = document.getElementById('fabMenu');
const declModal              = document.getElementById('declModal');
const declModalClose         = document.getElementById('declModalClose');
const declListView           = document.getElementById('declListView');
const declListSearch         = document.getElementById('declListSearch');
const declCustomerList       = document.getElementById('declCustomerList');
const declDetailView         = document.getElementById('declDetailView');
const declBackBtn            = document.getElementById('declBackBtn');
const declCustomerInfo       = document.getElementById('declCustomerInfo');
const declGenerateBtn        = document.getElementById('declGenerateBtn');
const declLinkResult         = document.getElementById('declLinkResult');
const declLinksList          = document.getElementById('declLinksList');
const declTableWrap          = document.getElementById('declTableWrap');
let declCustomerId = null;

// ── Work order modal refs ───────────────────────────────────────
const workOrderModal      = document.getElementById('workOrderModal');
const woModalTitle        = document.getElementById('woModalTitle');
const woModalClose        = document.getElementById('woModalClose');
const workOrderForm       = document.getElementById('workOrderForm');
const woStevilkaLabel     = document.getElementById('woStevilkaLabel');
const woStrankaInput      = document.getElementById('woStranka');
const woStrankaIdInput    = document.getElementById('woStrankaId');
const woStrankaSuggestions = document.getElementById('woStrankaSuggestions');
const woIzvajalecSel      = document.getElementById('woIzvajalec');
const woTipSel            = document.getElementById('woTip');
const woGerksListEl       = document.getElementById('woGerksList');
const woAddGerkBtn        = document.getElementById('woAddGerkBtn');
const woStrosekOcenaInput = document.getElementById('woStrosekOcena');
const woStrosekInput      = document.getElementById('woStrosek');
const woStatusSel         = document.getElementById('woStatus');
const woPodrobnostiInput  = document.getElementById('woPodrobnosti');
const woFormError         = document.getElementById('woFormError');
const woFormSuccess       = document.getElementById('woFormSuccess');
const woSaveBtn           = document.getElementById('woSaveBtn');
const woCancelBtn         = document.getElementById('woCancelBtn');

// ── Session guard ──────────────────────────────────────────────
async function initAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { window.location.replace('index.html'); return false; }
  currentUser = session.user;
  supabase.auth.onAuthStateChange((_e, s) => {
    if (!s) window.location.replace('index.html');
  });
  return true;
}

// ── Duration selects ───────────────────────────────────────────
function buildTimeOptions() {
  for (let h = 0; h <= 23; h++) roadHourSel.appendChild(new Option(String(h), String(h)));
  for (const m of ['00', '15', '30', '45']) roadMinSel.appendChild(new Option(m, m));
  roadHourSel.value = '0'; roadMinSel.value = '00';
}

function getDurationMins(hourSel, minSel) {
  return (parseInt(hourSel.value, 10) || 0) * 60 + (parseInt(minSel.value, 10) || 0);
}

// ── Date / month helpers ───────────────────────────────────────
const MONTHS_SL      = ['jan','feb','mar','apr','maj','jun','jul','avg','sep','okt','nov','dec'];
const MONTHS_SL_LONG = ['Januar','Februar','Marec','April','Maj','Junij','Julij','Avgust','September','Oktober','November','December'];

function fmtDate(iso) {
  const [y, m, d] = iso.split('-');
  return `${parseInt(d, 10)}. ${MONTHS_SL[parseInt(m, 10) - 1]} ${y}`;
}

function fmtDuration(mins) {
  if (!mins || mins <= 0) return '0h';
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

function todayISO() { return new Date().toISOString().slice(0, 10); }

function fmtTodayLong() {
  const d = new Date();
  return `${d.getDate()}. ${MONTHS_SL[d.getMonth()]} ${d.getFullYear()}`;
}

// ── Month navigation ───────────────────────────────────────────
function renderMonthLabel() {
  const [y, m] = currentMonth.split('-').map(Number);
  monthLabel.textContent = `${MONTHS_SL_LONG[m - 1]} ${y}`;
}

function changeMonth(delta) {
  const [y, m] = currentMonth.split('-').map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  currentMonth = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
  renderMonthLabel();
  renderLogs();
  updateStats();
}

prevMonthBtn.addEventListener('click', () => changeMonth(-1));
nextMonthBtn.addEventListener('click', () => changeMonth(1));

function filteredLogs() {
  return logs.filter(l => l.work_date.startsWith(currentMonth));
}

// ── Greeting ───────────────────────────────────────────────────
function renderGreeting(fullName) {
  const h = new Date().getHours();
  const word = h < 12 ? 'Dobro jutro' : h < 18 ? 'Dober dan' : 'Dober večer';
  greetingEl.textContent = `${word}, ${fullName.split(' ')[0]}!`;
  todayDateEl.textContent = fmtTodayLong();
}

// ── Stats ──────────────────────────────────────────────────────
function updateStats() {
  const fl = filteredLogs();
  statTotal.textContent = fl.length;
  const workMins = fl.reduce((s, l) => s + (l.work_duration || 0), 0);
  statWork.textContent = fmtDuration(workMins);
  const roadMins = fl.reduce((s, l) => s + (l.road_duration || 0), 0);
  statRoad.textContent = roadMins > 0 ? fmtDuration(roadMins) : '—';
  const allGerks = new Set(fl.flatMap(l => (l.work_log_gerks || []).map(g => g.gerk_code)));
  statGerk.textContent = allGerks.size || '—';
}

// ── Load logs ──────────────────────────────────────────────────
async function loadLogs() {
  logsList.innerHTML = `
    <div class="state-loading">
      <div class="spinner"></div>
      <p>Nalaganje...</p>
    </div>`;

  let query = supabase
    .from('work_logs')
    .select('*, work_log_gerks(*)')
    .order('work_date', { ascending: false })
    .order('created_at', { ascending: false });

  if (currentRole === 'admin' || currentRole === 'supervisor') {
    const { data: profs } = await supabase.from('profiles').select('id, full_name');
    profileMap = Object.fromEntries((profs ?? []).map(p => [p.id, p.full_name]));
  } else if (currentRole === 'supervisor') {
    const { data: profs } = await supabase
      .from('profiles')
      .select('id, full_name')
      .eq('organization', currentOrg);
    profileMap = Object.fromEntries((profs ?? []).map(p => [p.id, p.full_name]));
    const orgIds = (profs ?? []).map(p => p.id);
    if (orgIds.length) {
      query = query.in('operator_id', orgIds);
    } else {
      query = query.eq('operator_id', currentUser.id);
    }
  } else {
    query = query.eq('operator_id', currentUser.id);
  }

  const { data, error } = await query;

  if (error) {
    logsList.innerHTML = `<div class="state-empty"><p>Napaka pri nalaganju. Poskusite znova.</p></div>`;
    return;
  }

  logs = data ?? [];
  renderLogs();
  updateStats();
}

// ── Render ─────────────────────────────────────────────────────
function renderLogs() {
  const fl = filteredLogs();
  syncViewToggle();
  if (fl.length === 0) {
    logsList.className = 'logs-list';
    logsList.innerHTML = `
      <div class="state-empty">
        <p>Ni vpisov za ta mesec.<br>Dodajte prvega s tipko <strong>+</strong></p>
      </div>`;
    return;
  }
  viewMode === 'compact' ? renderLogsCompact(fl) : renderLogsCards(fl);
}

function renderLogsCards(fl) {
  logsList.className = 'logs-list';
  logsList.innerHTML = fl.map(log => {
    const gerks = log.work_log_gerks || [];
    const gerkBadges = gerks.map(g =>
      `<span class="log-gerk-badge">${escHtml(g.gerk_code)}</span>`
    ).join('') || '<span class="log-gerk-badge">—</span>';
    const totalHa = gerks.reduce((s, g) => s + (g.hectares || 0), 0);
    const haStr = totalHa > 0 ? ` · ${totalHa.toFixed(2)} ha` : '';
    const road = log.road_duration > 0
      ? `<div class="log-row"><span class="log-icon">🚗</span><span>Pot: ${fmtDuration(log.road_duration)}</span></div>` : '';
    const tractor = log.tractor
      ? `<div class="log-row"><span class="log-icon">🚜</span><span>${escHtml(log.tractor)}</span></div>` : '';
    const desc = log.description
      ? `<div class="log-row"><span class="log-desc">${escHtml(log.description)}</span></div>` : '';
    const operatorRow = currentRole === 'admin' || currentRole === 'supervisor'
      ? `<div class="log-row"><span class="log-operator-badge">${escHtml(profileMap[log.operator_id] ?? '—')}</span></div>` : '';
    return `
      <div class="log-card" role="listitem">
        <div class="log-card-top">
          <span class="log-date">${fmtDate(log.work_date)}</span>
          <span class="log-duration">${fmtDuration(log.work_duration)}</span>
        </div>
        <div class="log-card-body">
          ${operatorRow}
          <div class="log-row">${gerkBadges}${haStr ? `<span class="log-ha-text">${haStr}</span>` : ''}</div>
          ${road}${tractor}${desc}
        </div>
        <div class="log-card-actions">
          <button class="btn-danger-outline" data-action="delete" data-id="${log.id}">Izbriši</button>
        </div>
      </div>`;
  }).join('');
  wireLogButtons();
}

const DEL_ICON = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true"><path d="M2 3.5h10M5 3.5V2h4v1.5M3.5 3.5l.5 8h6l.5-8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

function renderLogsCompact(fl) {
  logsList.className = 'logs-list logs-list--compact';
  const header = `
    <div class="lc-header" aria-hidden="true">
      <span>Datum</span>
      <span>Trajanje</span>
      <span>GERKI</span>
      <span>Ha</span>
      <span></span>
    </div>`;

  const rows = fl.map(log => {
    const gerks = log.work_log_gerks || [];
    const gerkCodes = gerks.map(g => escHtml(g.gerk_code)).join(', ') || '—';
    const totalHa = gerks.reduce((s, g) => s + (g.hectares || 0), 0);
    const haStr = totalHa > 0 ? totalHa.toFixed(2) : '—';

    const extras = [
      currentRole === 'admin' || currentRole === 'supervisor' ? escHtml(profileMap[log.operator_id] ?? '—') : null,
      log.road_duration > 0 ? `Pot: ${fmtDuration(log.road_duration)}` : null,
      log.tractor ? `Traktor: ${escHtml(log.tractor)}` : null,
      log.description ? escHtml(log.description) : null,
    ].filter(Boolean);
    const extraRow = extras.length
      ? `<p class="lc-desc-row">${extras.join(' · ')}</p>` : '';

    return `
      <div class="log-compact" role="listitem">
        <span class="lc-date">${fmtDate(log.work_date)}</span>
        <span class="lc-dur">${fmtDuration(log.work_duration)}</span>
        <span class="lc-gerk">${gerkCodes}</span>
        <span class="lc-ha">${haStr}</span>
        <div class="lc-actions">
          <button class="lc-btn lc-btn--danger" data-action="delete" data-id="${log.id}" title="Izbriši">${DEL_ICON}</button>
        </div>
        ${extraRow}
      </div>`;
  }).join('');

  logsList.innerHTML = header + rows;
  wireLogButtons();
}

function syncViewToggle() {
  viewCardsBtn?.classList.toggle('active', viewMode === 'cards');
  viewListBtn?.classList.toggle('active',  viewMode === 'compact');
}

viewCardsBtn?.addEventListener('click', () => { viewMode = 'cards';   renderLogs(); });
viewListBtn?.addEventListener('click',  () => { viewMode = 'compact'; renderLogs(); });

function escHtml(str) {
  if (!str) return '';
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Tractor history (localStorage) ────────────────────────────
function getTractorHistory() {
  return JSON.parse(localStorage.getItem('wt_tractors') || '[]');
}
function saveTractorToHistory(name) {
  if (!name) return;
  const list = getTractorHistory().filter(t => t !== name);
  list.unshift(name);
  localStorage.setItem('wt_tractors', JSON.stringify(list.slice(0, 15)));
}
function updateTractorDatalist() {
  const dl = document.getElementById('tractorList');
  if (dl) dl.innerHTML = getTractorHistory().map(t => `<option value="${escHtml(t)}">`).join('');
}

// ── GERK autocomplete ──────────────────────────────────────────
// Reads WorkTracker's own fields table (not the CRM's FIELD) — the two
// were consolidated so there's a single source of truth for what fields
// exist. See supabase/migration_import_field_only_rows.sql.
async function loadFields() {
  const { data } = await supabase
    .from('fields')
    .select('cadastre_id, name, area_ha, centroid_lat, centroid_lng, customers(naziv, company_name)')
    .order('name');
  const seen = new Set();
  fields = (data ?? [])
    .filter(f => f.cadastre_id)
    .map(f => ({
      code:     f.cadastre_id,
      name:     f.name ?? null,
      area:     f.area_ha ?? null,
      lat:      f.centroid_lat ?? null,
      lng:      f.centroid_lng ?? null,
      customer: f.customers?.naziv || f.customers?.company_name || null,
    }))
    .filter(f => { if (seen.has(f.code)) return false; seen.add(f.code); return true; });
}

function filterFields(query) {
  if (!query) return [];
  const q = query.toLowerCase();
  return fields
    .filter(f =>
      f.code.toLowerCase().includes(q) ||
      (f.name     && f.name.toLowerCase().includes(q)) ||
      (f.customer && f.customer.toLowerCase().includes(q))
    )
    .slice(0, 8);
}

function attachGerkAutocomplete(inputEl, suggestionsEl, hintEl, onSelect) {
  inputEl.addEventListener('input', () => {
    hintEl.hidden = true;
    showSuggestionsInto(suggestionsEl, filterFields(inputEl.value.trim()));
  });
  inputEl.addEventListener('focus', () => {
    if (inputEl.value.trim()) showSuggestionsInto(suggestionsEl, filterFields(inputEl.value.trim()));
  });
  inputEl.addEventListener('blur', () => {
    setTimeout(() => { suggestionsEl.hidden = true; }, 150);
  });
  suggestionsEl.addEventListener('mousedown', e => {
    const item = e.target.closest('.gerk-suggestion-item');
    if (!item) return;
    const code = item.dataset.code;
    inputEl.value = code;
    suggestionsEl.hidden = true;
    const f = fields.find(f => f.code === code);
    if (f) {
      const parts = [f.name, f.customer, f.area ? `${f.area} ha` : null].filter(Boolean);
      if (parts.length) { hintEl.textContent = parts.join(' · '); hintEl.hidden = false; }
      if (onSelect) onSelect(f);
    }
  });
}

function showSuggestionsInto(suggestionsEl, matches) {
  if (!matches.length) { suggestionsEl.hidden = true; return; }
  suggestionsEl.innerHTML = matches.map(f => {
    const meta = [f.name, f.customer, f.area ? `${f.area} ha` : null].filter(Boolean);
    return `
      <li class="gerk-suggestion-item" data-code="${escHtml(f.code)}">
        <span class="gerk-suggestion-code">${escHtml(f.code)}</span>
        ${meta.length ? `<span class="gerk-suggestion-meta">${escHtml(meta.join(' · '))}</span>` : ''}
      </li>`;
  }).join('');
  suggestionsEl.hidden = false;
}

function addGerkRow(container = woGerksListEl, code = '', hectares = '', lokacija = '') {
  const row = document.createElement('div');
  row.className = 'gerk-row';
  row.innerHTML = `
    <div class="gerk-row-main">
      <div class="gerk-wrap">
        <input type="text" class="field-input gerk-code-input"
               placeholder="GERK številka ali ime" autocomplete="off">
        <ul class="gerk-suggestions" hidden></ul>
        <p class="field-hint gerk-hint" hidden></p>
      </div>
      <input type="number" class="field-input gerk-ha-input"
             placeholder="ha" step="0.0001" min="0" max="9999">
      <button type="button" class="gerk-remove-btn" aria-label="Odstrani">✕</button>
    </div>
    <input type="text" class="field-input gerk-lokacija-input"
           placeholder="Lokacija (npr. GPS koordinate)" autocomplete="off">`;

  const codeInput     = row.querySelector('.gerk-code-input');
  const haInput       = row.querySelector('.gerk-ha-input');
  const lokacijaInput = row.querySelector('.gerk-lokacija-input');
  const suggestionsEl = row.querySelector('.gerk-suggestions');
  const hintEl        = row.querySelector('.gerk-hint');
  const removeBtn     = row.querySelector('.gerk-remove-btn');

  codeInput.value = code;
  if (hectares !== '' && hectares != null) haInput.value = hectares;
  if (lokacija) lokacijaInput.value = lokacija;

  if (code) {
    const f = fields.find(f => f.code === code);
    if (f) {
      const parts = [f.name, f.customer, f.area ? `${f.area} ha` : null].filter(Boolean);
      if (parts.length) { hintEl.textContent = parts.join(' · '); hintEl.hidden = false; }
    }
  }

  attachGerkAutocomplete(codeInput, suggestionsEl, hintEl, f => {
    if (f.area != null && !haInput.value) haInput.value = f.area;
  });

  removeBtn.addEventListener('click', () => {
    row.remove();
    if (!container.querySelector('.gerk-row')) addGerkRow(container);
  });

  container.appendChild(row);
  return codeInput;
}

function getFormGerks(container = woGerksListEl) {
  return Array.from(container.querySelectorAll('.gerk-row')).map(row => ({
    code:     row.querySelector('.gerk-code-input').value.trim(),
    hectares: row.querySelector('.gerk-ha-input').value
              ? parseFloat(row.querySelector('.gerk-ha-input').value) : null,
    lokacija: row.querySelector('.gerk-lokacija-input').value.trim() || null,
  })).filter(g => g.code);
}

// ── Work log GERK entry table (fixed to the work order's fields) ──
// Rows = the work order's planned fields, plus any field today's log
// already carries but the current plan no longer lists.
// Every fetched entry that ISN'T "me, on the date currently being viewed"
// (that one is already represented by the row's own Start/Konec state) —
// grouped by GERK so each row can show who else has worked it, and when.
function otherGerkEntriesByCode() {
  const map = {};
  for (const e of currentAllGerkEntries) {
    const wl = e.work_logs;
    if (wl.operator_id === currentUser.id && wl.work_date === currentDetailDate) continue;
    (map[e.gerk_code] ??= []).push(e);
  }
  return map;
}

function buildGerkPlanRows(workOrder, todaysGerks) {
  const planFields = workOrder?.delovni_nalogi_gerki || [];
  const logByCode   = Object.fromEntries((todaysGerks || []).map(g => [g.gerk_code, g]));
  const othersByCode = otherGerkEntriesByCode();

  const rows = planFields.map(pf => ({
    code:      pf.gerk_code,
    gerkId:    pf.id,
    hectares:  pf.kolicina_ha ?? logByCode[pf.gerk_code]?.hectares ?? null,
    lokacija:  pf.lokacija ?? null,
    startTime: logByCode[pf.gerk_code]?.start_time ?? null,
    endTime:   logByCode[pf.gerk_code]?.end_time ?? null,
    duration:  logByCode[pf.gerk_code]?.duration ?? null,
    completed: logByCode[pf.gerk_code]?.completed ?? false,
    samples:   pf.delovni_nalogi_vzorci || [],
    otherEntries: othersByCode[pf.gerk_code] || [],
  }));

  const planCodes = new Set(planFields.map(pf => pf.gerk_code));
  (todaysGerks || []).filter(g => !planCodes.has(g.gerk_code)).forEach(g => {
    rows.push({
      code: g.gerk_code, hectares: g.hectares, lokacija: null,
      startTime: g.start_time, endTime: g.end_time, duration: g.duration ?? null, completed: g.completed ?? false,
      samples: [],
      otherEntries: othersByCode[g.gerk_code] || [],
    });
  });

  return rows;
}

function fmtHM(mins) {
  if (!mins) return '0m';
  const h = Math.floor(mins / 60), m = mins % 60;
  return m ? `${h}h ${m}m` : `${h}h`;
}

// Local HH:MM for display next to the Start/Konec buttons.
function fmtClock(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// Short d.m.yyyy for the samples panel; dash for unset dates (common in
// the historical import — sampling/sending dates weren't always recorded).
function fmtSampleDate(isoDate) {
  if (!isoDate) return '—';
  const [y, m, d] = isoDate.split('-');
  return `${parseInt(d, 10)}.${parseInt(m, 10)}.${y}`;
}

// Same, but as a value an <input type="time"> will accept.
function toTimeInputValue(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// ── Vzorčenje (sampling_note) action dropdown / sampling depth ──
// admin-editable, everyone else read-only. Matches the "Admins can
// manage samples" RLS policy: only admins can actually write, so only
// admins get the dropdown.
//
// The action concept lives in sampling_note, not a separate column —
// that's already where "ne pobereš" shows up 251 times from the
// original import. "združi" (bare, no group number, 148 rows) is kept
// as its own option alongside združi_1..5: the original Excel used
// cell color to show which segments group together, and only the
// word itself survived the import, not which group — so these rows
// genuinely don't have a group number to default to.
const SAMPLE_ACTIONS = ['ne pobereš', 'združi', 'združi_1', 'združi_2', 'združi_3', 'združi_4', 'združi_5'];
const SAMPLE_DEPTHS  = [12, 20, 25, 30, 60, 90];

function renderSamplingCell(s) {
  if (currentRole !== 'admin') {
    return s.sampling_note ? escHtml(s.sampling_note) : fmtSampleDate(s.sampling_date);
  }
  const matchesAction = s.sampling_note && SAMPLE_ACTIONS.includes(s.sampling_note);
  const opts = ['<option value="">-</option>']
    .concat(SAMPLE_ACTIONS.map(a => `<option value="${escHtml(a)}"${s.sampling_note === a ? ' selected' : ''}>${escHtml(a)}</option>`))
    .join('');
  const select = `<select class="sample-field-input" data-sample-id="${escHtml(s.id)}" data-field="sampling_note">${opts}</select>`;
  // Raw import text/date fragments the dropdown can't represent as one
  // of its own options — keep it visible instead of silently hiding it
  // behind a "-" selection.
  const raw = !matchesAction && (s.sampling_note || s.sampling_date)
    ? `<div class="sample-raw-note">${s.sampling_note ? escHtml(s.sampling_note) : fmtSampleDate(s.sampling_date)}</div>`
    : '';
  return `${select}${raw}`;
}

function renderSampleDepthCell(s) {
  if (currentRole !== 'admin') return s.sampling_depth_cm ? `${s.sampling_depth_cm} cm` : '—';
  const opts = ['<option value="">-</option>']
    .concat(SAMPLE_DEPTHS.map(d => `<option value="${d}"${s.sampling_depth_cm === d ? ' selected' : ''}>${d} cm</option>`))
    .join('');
  return `<select class="sample-field-input" data-sample-id="${escHtml(s.id)}" data-field="sampling_depth_cm">${opts}</select>`;
}

function renderSampleAreaCell(s) {
  if (currentRole !== 'admin') return s.area_ha != null ? `${s.area_ha} ha` : '—';
  return `<input type="number" step="0.01" min="0" class="sample-field-input sample-area-input"
            data-sample-id="${escHtml(s.id)}" data-field="area_ha" value="${s.area_ha ?? ''}" placeholder="ha">`;
}

// Updates one sample's action/depth/area in place — direct table
// write (no RPC needed, RLS already restricts this to admins) — and
// patches the in-memory copy so it stays correct if the panel
// re-renders without a full reload.
async function updateSampleField(fieldEl) {
  const sampleId = fieldEl.dataset.sampleId;
  const field    = fieldEl.dataset.field;
  let value = fieldEl.value === '' ? null : fieldEl.value;
  if (field === 'sampling_depth_cm' && value !== null) value = parseInt(value, 10);
  if (field === 'area_ha' && value !== null) value = parseFloat(value);

  fieldEl.disabled = true;
  try {
    const { error } = await supabase.from('delovni_nalogi_vzorci').update({ [field]: value }).eq('id', sampleId);
    if (error) throw error;
    for (const g of currentDetailWorkOrder.delovni_nalogi_gerki || []) {
      const sample = (g.delovni_nalogi_vzorci || []).find(s => s.id === sampleId);
      if (sample) { sample[field] = value; break; }
    }
  } catch (e) {
    showFormError('Napaka pri shranjevanju vzorca.');
  } finally {
    fieldEl.disabled = false;
  }
}

function renderWorkLogGerkRows(rows) {
  if (!rows.length) {
    workLogGerkRowsEl.innerHTML = `<p class="field-hint">Ta delovni nalog nima dodanih GERKOV.</p>`;
    return;
  }
  workLogGerkRowsEl.innerHTML = rows.map(r => {
    const f = fields.find(f => f.code === r.code);
    const name = f?.name || '';
    const ha   = r.hectares != null ? `${Number(r.hectares).toFixed(2)} ha` : (f?.area ? `${f.area} ha` : '');
    const meta = [ha, r.lokacija].filter(Boolean).join(' · ');
    const completed = !!r.completed;
    const hasStart  = !!r.startTime;
    const samples   = r.samples || [];
    const others    = r.otherEntries || [];
    return `
      <div class="wlg-row${completed ? ' wlg-row--completed' : ''}" data-code="${escHtml(r.code)}"
           data-start="${r.startTime || ''}" data-end="${r.endTime || ''}" data-duration="${r.duration ?? ''}">
        <div class="wlg-info">
          <span class="wlg-code-line">
            <span class="wlg-code">${escHtml(r.code)}</span>${name ? ` <span class="wlg-name">${escHtml(name)}</span>` : ''}
            ${f?.lat != null && f?.lng != null ? `<a class="wlg-field-map" href="https://www.google.com/maps?q=${f.lat},${f.lng}" target="_blank" rel="noopener" aria-label="Odpri na zemljevidu">📍</a>` : ''}
          </span>
          ${meta ? `<span class="wlg-meta">${escHtml(meta)}</span>` : ''}
        </div>
        <div class="wlg-times">
          <button type="button" class="wlg-toggle-btn" data-action="wlg-start">Start</button>
          <span class="wlg-time-value" data-role="start-value">${fmtClock(r.startTime)}</span>
          <button type="button" class="wlg-toggle-btn" data-action="wlg-end" ${hasStart ? '' : 'disabled'}>Konec</button>
          <span class="wlg-time-value" data-role="end-value">${fmtClock(r.endTime)}</span>
          <button type="button" class="btn btn-icon wlg-edit-btn" data-action="wlg-edit-toggle" aria-label="Uredi čas">✎</button>
        </div>
        <div class="wlg-edit-panel" hidden>
          <label class="wlg-edit-label">Datum
            <input type="date" class="wlg-edit-date" max="${todayISO()}" value="${currentDetailDate}">
          </label>
          <label class="wlg-edit-label">Začetek
            <input type="time" class="wlg-edit-start" value="${toTimeInputValue(r.startTime)}">
          </label>
          <label class="wlg-edit-label">Konec
            <input type="time" class="wlg-edit-end" value="${toTimeInputValue(r.endTime)}">
          </label>
          <button type="button" class="btn btn-secondary btn-sm" data-action="wlg-edit-save">Shrani</button>
          <button type="button" class="btn btn-secondary btn-sm" data-action="wlg-edit-cancel">Prekliči</button>
        </div>
        ${others.length ? `
        <div class="wlg-others">
          ${others.map(o => {
            const opName = o.work_logs.profiles?.full_name || '—';
            const when   = fmtSampleDate(o.work_logs.work_date);
            const time   = o.end_time ? `${fmtClock(o.start_time)}–${fmtClock(o.end_time)}` : (o.start_time ? 'v teku' : '');
            return `<span class="wlg-others-item">${o.completed ? '✓' : '•'} ${escHtml(opName)} · ${when}${time ? ' · ' + time : ''}</span>`;
          }).join('')}
        </div>` : ''}
        ${renderSamplesSection(samples, r.gerkId)}
      </div>`;
  }).join('');

  wireGerkRowButtons();
}

// Admins can always see + add segments (even zero today — that's the
// point of the + button), everyone else only sees the panel when
// there's actually something to show.
function renderSamplesSection(samples, gerkId) {
  if (!samples.length && currentRole !== 'admin') return '';
  const addBtn = currentRole === 'admin' && gerkId
    ? `<button type="button" class="btn btn-secondary btn-sm wlg-add-sample" data-action="wlg-add-sample" data-gerk-id="${escHtml(gerkId)}">+ Dodaj segment</button>`
    : '';
  return `
        <button type="button" class="wlg-samples-toggle wlg-samples-toggle--open" data-action="wlg-samples-toggle">
          <span>${samples.length} ${samples.length === 1 ? 'vzorec' : 'vzorcev'}</span>
          <span class="wlg-samples-chevron" aria-hidden="true">▾</span>
        </button>
        <div class="wlg-samples-panel">
          <table class="wlg-samples-table">
            <thead><tr><th>Št. vzorca</th><th>Ha</th><th>Vzorčenje</th><th>Pošiljanje</th><th>Globina</th></tr></thead>
            <tbody>
              ${samples.map(s => `
                <tr>
                  <td>${escHtml(s.sample_no)}</td>
                  <td>${renderSampleAreaCell(s)}</td>
                  <td>${renderSamplingCell(s)}</td>
                  <td>${s.sending_note ? escHtml(s.sending_note) : fmtSampleDate(s.sending_date)}</td>
                  <td>${renderSampleDepthCell(s)}</td>
                </tr>`).join('')}
            </tbody>
          </table>
          ${addBtn}
        </div>`;
}

function updateOrderHeader() {
  const wo = currentDetailWorkOrder;
  const rows = Array.from(workLogGerkRowsEl.querySelectorAll('.wlg-row'));
  const allCompleted = rows.length > 0 && rows.every(r => r.classList.contains('wlg-row--completed'));
  const totalSec = rows.reduce((s, r) => s + (parseInt(r.dataset.duration, 10) || 0), 0);
  const totalMin = Math.round(totalSec / 60);

  woStartBtn.classList.toggle('btn-started', wo.status !== 'Plan');
  if (wo.status === 'Plan') {
    woStartBtn.textContent = 'Prevzemi nalog';
    woStartBtn.disabled = false;
  } else {
    woStartBtn.textContent = allCompleted ? 'Končan' : 'V delu';
    woStartBtn.disabled = true;
  }

  // Everyone who's actually logged a GERK on this order, not just whoever
  // originally claimed it — a second operator picking up mid-order doesn't
  // replace the first in this list, both show.
  const contributors = [...new Set(currentAllGerkEntries.map(e => e.work_logs.profiles?.full_name).filter(Boolean))];
  const izvajaLabel = contributors.length ? contributors.join(', ') : wo.profiles?.full_name;
  const metaParts = [];
  if (wo.status !== 'Plan' && izvajaLabel) metaParts.push(`Izvaja: ${izvajaLabel}`);
  if (totalMin > 0) metaParts.push(`Skupaj: ${fmtHM(totalMin)}`);
  woHeaderMeta.textContent = metaParts.join(' · ');
}

// ── Modal ──────────────────────────────────────────────────────
let currentDetailWorkOrder = null;
let currentDetailLogId     = null;
let currentDetailDate      = null;
let currentRoadTimeEntries = [];
let currentAllGerkEntries  = []; // every operator's work_log_gerks for this work order — powers the "who else worked on this" view

async function openWorkOrderDetail(workOrder) {
  currentDetailWorkOrder  = workOrder;
  currentDetailDate       = todayISO();

  modalTitle.textContent = 'Delovni nalog';
  hideFormFeedback();
  updateTractorDatalist();

  const stranka = workOrder.customers?.naziv || workOrder.customers?.company_name;
  workLogOrderLabel.textContent = [workOrder.stevilka, stranka].filter(Boolean).join(' — ');

  workLogDateInput.max   = todayISO();
  workLogDateInput.value = currentDetailDate;

  woMapsLink.hidden = true;
  loadWorkOrderCenterPoint(workOrder.id); // fire-and-forget, don't block modal open on a geometry query

  await loadDetailForDate();

  formModal.hidden = false;
  document.body.style.overflow = 'hidden';
}

// Combines every GERK's CENTER_POINT on this work order into one
// point server-side (see get_work_order_center_point). Guards against
// the modal having moved on to a different work order by the time
// this resolves (rapid open/close/reopen).
async function loadWorkOrderCenterPoint(workOrderId) {
  const { data, error } = await supabase.rpc('get_work_order_center_point', { p_work_order_id: workOrderId });
  if (error || currentDetailWorkOrder?.id !== workOrderId) return;
  const result = Array.isArray(data) ? data[0] : data;
  if (result?.lat == null || result?.lng == null) return;
  woMapsLink.href = `https://www.google.com/maps?q=${result.lat},${result.lng}`;
  woMapsLink.hidden = false;
}

// Re-fetches and re-renders the modal's contents for currentDetailDate —
// called on open, and again whenever the date picker changes, since each
// work order can carry at most one work_logs row per operator per day.
async function loadDetailForDate() {
  currentDetailLogId     = null;
  ensureTodaysLogPromise = null;

  roadHourSel.value = '0'; roadMinSel.value = '00';
  tractorInput.value = '';
  descInput.value = '';

  const [{ data: existingLog }, { data: allEntries }] = await Promise.all([
    supabase
      .from('work_logs')
      .select('id, road_duration, tractor, description, work_log_gerks(gerk_code, hectares, start_time, end_time, duration, completed), work_log_road_time(id, minutes)')
      .eq('operator_id', currentUser.id)
      .eq('work_order_id', currentDetailWorkOrder.id)
      .eq('work_date', currentDetailDate)
      .maybeSingle(),
    // Every operator's GERK entries for this work order (any date) — lets
    // someone taking over mid-order see what's already been done, and by whom.
    supabase
      .from('work_log_gerks')
      .select('gerk_code, start_time, end_time, duration, completed, work_logs!inner(operator_id, work_date, profiles(full_name))')
      .eq('work_logs.work_order_id', currentDetailWorkOrder.id),
  ]);

  if (existingLog) {
    currentDetailLogId = existingLog.id;
    tractorInput.value = existingLog.tractor || '';
    descInput.value    = existingLog.description || '';
  }

  currentRoadTimeEntries = existingLog?.work_log_road_time || [];
  renderRoadTimeList();

  currentAllGerkEntries = allEntries || [];
  renderWorkLogGerkRows(buildGerkPlanRows(currentDetailWorkOrder, existingLog?.work_log_gerks || []));
  updateOrderHeader();
}

workLogDateInput.addEventListener('change', () => {
  currentDetailDate = workLogDateInput.value || todayISO();
  hideFormFeedback();
  loadDetailForDate();
});

function closeModal() {
  formModal.hidden = true;
  document.body.style.overflow = '';
  // Time logged via the live Start/Stop timers writes straight to Supabase
  // without updating the in-memory `logs` array — refresh it so Evidenca
  // dela reflects what was just logged.
  loadLogs();
}

function hideFormFeedback() {
  formError.hidden   = true;
  formSuccess.hidden = true;
}

function showFormError(msg) {
  formError.textContent = msg;
  formError.hidden = false;
  formSuccess.hidden = true;
}

function showFormSuccess(msg) {
  formSuccess.textContent = msg;
  formSuccess.hidden = false;
  formError.hidden = true;
}

// ── Live time tracking: today's work_logs + work_log_gerks ──────
// Both RPCs below do their own find-or-create of the day's work_logs
// row and the field's work_log_gerks row server-side, in one round
// trip — see supabase/migration_gerk_timer_rpc.sql. ensureTodaysLog()
// still handles that same find-or-create client-side, but only for the
// road-duration/tractor/notes fields, which aren't covered by either RPC.
let ensureTodaysLogPromise = null;

async function ensureTodaysLog() {
  if (currentDetailLogId) return currentDetailLogId;
  // Two fields saved in quick succession would otherwise both race
  // through the check-then-insert below before either resolves — share
  // the same in-flight promise so only one insert is ever attempted.
  if (ensureTodaysLogPromise) return ensureTodaysLogPromise;

  ensureTodaysLogPromise = (async () => {
    const { data: existing } = await supabase
      .from('work_logs')
      .select('id')
      .eq('operator_id', currentUser.id)
      .eq('work_order_id', currentDetailWorkOrder.id)
      .eq('work_date', currentDetailDate)
      .maybeSingle();

    if (existing) { currentDetailLogId = existing.id; return existing.id; }

    const { data, error } = await supabase
      .from('work_logs')
      .insert({ operator_id: currentUser.id, work_order_id: currentDetailWorkOrder.id, work_date: currentDetailDate, work_duration: 0 })
      .select('id')
      .single();

    if (error) {
      // Unique violation from a concurrent insert (e.g. a second tab)
      // that won the race — fetch the row it created instead of failing.
      if (error.code === '23505') {
        const { data: raceWinner, error: fetchErr } = await supabase
          .from('work_logs')
          .select('id')
          .eq('operator_id', currentUser.id)
          .eq('work_order_id', currentDetailWorkOrder.id)
          .eq('work_date', currentDetailDate)
          .single();
        if (fetchErr) throw fetchErr;
        currentDetailLogId = raceWinner.id;
        return raceWinner.id;
      }
      throw error;
    }

    currentDetailLogId = data.id;
    return data.id;
  })();

  try {
    return await ensureTodaysLogPromise;
  } finally {
    ensureTodaysLogPromise = null;
  }
}

// Applies an RPC's returned row to the DOM: timer/duration display,
// completed styling, and the Start/Stop button state.
function applyGerkRowUpdate(row, updated) {
  currentDetailLogId   = updated.log_id;
  row.dataset.start    = updated.start_time || '';
  row.dataset.end      = updated.end_time || '';
  row.dataset.duration = updated.duration ?? '';

  row.classList.toggle('wlg-row--completed', !!updated.completed);
  row.querySelector('[data-role="start-value"]').textContent = fmtClock(updated.start_time);
  row.querySelector('[data-role="end-value"]').textContent   = fmtClock(updated.end_time);
  row.querySelector('[data-action="wlg-end"]').disabled = !updated.start_time;

  row.querySelector('.wlg-edit-panel').hidden = true;
  row.querySelector('.wlg-edit-start').value = toTimeInputValue(updated.start_time);
  row.querySelector('.wlg-edit-end').value   = toTimeInputValue(updated.end_time);

  updateOrderHeader();
}

async function startGerk(btn) {
  const row = btn.closest('.wlg-row');
  btn.disabled = true;
  try {
    const { data, error } = await supabase.rpc('start_gerk', {
      p_work_order_id: currentDetailWorkOrder.id,
      p_gerk_code:      row.dataset.code,
      p_work_date:      currentDetailDate,
    });
    if (error) throw error;
    applyGerkRowUpdate(row, Array.isArray(data) ? data[0] : data);
  } catch (e) {
    showFormError('Napaka pri shranjevanju časa.');
  } finally {
    btn.disabled = false;
  }
}

async function endGerk(btn) {
  const row = btn.closest('.wlg-row');
  btn.disabled = true;
  try {
    const { data, error } = await supabase.rpc('end_gerk', {
      p_work_order_id: currentDetailWorkOrder.id,
      p_gerk_code:      row.dataset.code,
      p_work_date:      currentDetailDate,
    });
    if (error) throw error;
    applyGerkRowUpdate(row, Array.isArray(data) ? data[0] : data);
  } catch (e) {
    showFormError(e.message || 'Napaka pri shranjevanju časa.');
  } finally {
    btn.disabled = false;
  }
}

function toggleGerkEdit(btn) {
  const row = btn.closest('.wlg-row');
  const panel = row.querySelector('.wlg-edit-panel');
  panel.hidden = !panel.hidden;
  if (!panel.hidden) {
    row.querySelector('.wlg-edit-date').value  = currentDetailDate;
    row.querySelector('.wlg-edit-start').value = toTimeInputValue(row.dataset.start);
    row.querySelector('.wlg-edit-end').value   = toTimeInputValue(row.dataset.end);
  }
}

function cancelGerkEdit(btn) {
  btn.closest('.wlg-edit-panel').hidden = true;
}

function toggleGerkSamples(btn) {
  const panel = btn.closest('.wlg-row').querySelector('.wlg-samples-panel');
  panel.hidden = !panel.hidden;
  btn.classList.toggle('wlg-samples-toggle--open', !panel.hidden);
}

// Combines the modal's selected work_date with an <input type="time">
// value (local HH:MM, no timezone) into a proper timestamptz.
function timeInputToISO(dateStr, timeVal) {
  if (!timeVal) return null;
  return new Date(`${dateStr}T${timeVal}:00`).toISOString();
}

async function saveGerkEdit(btn) {
  const row      = btn.closest('.wlg-row');
  const dateVal  = row.querySelector('.wlg-edit-date').value || currentDetailDate;
  const startVal = row.querySelector('.wlg-edit-start').value;
  const endVal   = row.querySelector('.wlg-edit-end').value;
  const moved    = dateVal !== currentDetailDate;

  btn.disabled = true;
  try {
    const { data, error } = await supabase.rpc('set_gerk_times', {
      p_work_order_id: currentDetailWorkOrder.id,
      p_gerk_code:      row.dataset.code,
      p_start_time:     timeInputToISO(dateVal, startVal),
      p_end_time:       timeInputToISO(dateVal, endVal),
      p_work_date:      dateVal,
      p_previous_work_date: currentDetailDate,
    });
    if (error) throw error;
    if (moved) {
      // Entry now belongs to a different day's log. Rows are one-per-
      // planned-field, not one-per-entry, so this row stays in the list —
      // it just needs to drop back to "not started" for currentDetailDate.
      // Reloading is simplest and matches what a fresh open would show.
      await loadDetailForDate();
      showFormSuccess(`Vnos prestavljen na ${fmtSampleDate(dateVal)}.`);
    } else {
      applyGerkRowUpdate(row, Array.isArray(data) ? data[0] : data);
    }
  } catch (e) {
    showFormError(e.message || 'Napaka pri shranjevanju.');
  } finally {
    btn.disabled = false;
  }
}

function wireGerkRowButtons() {
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-start"]').forEach(btn => {
    btn.addEventListener('click', () => startGerk(btn));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-end"]').forEach(btn => {
    btn.addEventListener('click', () => endGerk(btn));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-edit-toggle"]').forEach(btn => {
    btn.addEventListener('click', () => toggleGerkEdit(btn));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-edit-save"]').forEach(btn => {
    btn.addEventListener('click', () => saveGerkEdit(btn));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-edit-cancel"]').forEach(btn => {
    btn.addEventListener('click', () => cancelGerkEdit(btn));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-samples-toggle"]').forEach(btn => {
    btn.addEventListener('click', () => toggleGerkSamples(btn));
  });
  workLogGerkRowsEl.querySelectorAll('.sample-field-input').forEach(sel => {
    sel.addEventListener('change', () => updateSampleField(sel));
  });
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-add-sample"]').forEach(btn => {
    btn.addEventListener('click', () => addSample(btn));
  });
}

// Adds one new segment/sample row for a GERK — sample_no auto-suggested
// as (highest existing number for that GERK) + 1, everything else left
// blank to fill in afterward via the existing dropdowns/inputs.
// currentDetailWorkOrder.delovni_nalogi_gerki isn't kept in sync by
// loadDetailForDate() (that only re-fetches work_logs/work_log_gerks
// for the day), so the freshly inserted row is fetched directly and
// patched in before re-rendering.
async function addSample(btn) {
  const gerkId = btn.dataset.gerkId;
  const gerk = (currentDetailWorkOrder.delovni_nalogi_gerki || []).find(g => g.id === gerkId);
  const existing = gerk?.delovni_nalogi_vzorci || [];
  const maxNo = existing.reduce((max, s) => {
    const n = parseInt(s.sample_no, 10);
    return Number.isFinite(n) && n > max ? n : max;
  }, 0);

  btn.disabled = true;
  try {
    const { data, error } = await supabase
      .from('delovni_nalogi_vzorci')
      .insert({ delovni_nalog_gerk_id: gerkId, sample_no: String(maxNo + 1) })
      .select('id, sample_no, sampling_date, sending_date, sampling_note, sending_note, sampling_depth_cm, area_ha')
      .single();
    if (error) throw error;

    gerk.delovni_nalogi_vzorci = [...existing, data];
    await loadDetailForDate();
  } catch (e) {
    showFormError(e.message || 'Napaka pri dodajanju segmenta.');
  } finally {
    btn.disabled = false;
  }
}

// ── Čas na poti: multiple add-a-line entries, summed server-side ──
function renderRoadTimeList() {
  if (!currentRoadTimeEntries.length) {
    roadTimeListEl.innerHTML = '';
    return;
  }
  roadTimeListEl.innerHTML = currentRoadTimeEntries.map(e => `
    <div class="road-time-row" data-id="${e.id}">
      <span><span class="road-time-type">${escHtml(e.vehicle_type || 'Traktor')}</span> · ${fmtHM(e.minutes)}</span>
      <button type="button" class="road-time-remove" data-action="road-remove" aria-label="Odstrani">✕</button>
    </div>`).join('');

  roadTimeListEl.querySelectorAll('[data-action="road-remove"]').forEach(btn => {
    btn.addEventListener('click', () => removeRoadTime(btn.closest('.road-time-row').dataset.id));
  });
}

async function addRoadTime() {
  const minutes = getDurationMins(roadHourSel, roadMinSel);
  if (!minutes) return;

  roadAddBtn.disabled = true;
  try {
    const { data, error } = await supabase.rpc('add_road_time', {
      p_work_order_id: currentDetailWorkOrder.id,
      p_minutes:        minutes,
      p_vehicle_type:   roadTypeSel.value,
      p_work_date:      currentDetailDate,
    });
    if (error) throw error;
    const result = Array.isArray(data) ? data[0] : data;
    currentDetailLogId     = result.log_id;
    currentRoadTimeEntries = result.entries || [];
    renderRoadTimeList();
    roadHourSel.value = '0'; roadMinSel.value = '00';
  } catch (e) {
    showFormError('Napaka pri shranjevanju časa na poti.');
  } finally {
    roadAddBtn.disabled = false;
  }
}

async function removeRoadTime(entryId) {
  try {
    const { data, error } = await supabase.rpc('remove_road_time', { p_entry_id: entryId });
    if (error) throw error;
    const result = Array.isArray(data) ? data[0] : data;
    currentRoadTimeEntries = result.entries || [];
    renderRoadTimeList();
  } catch (e) {
    showFormError('Napaka pri brisanju.');
  }
}

roadAddBtn.addEventListener('click', addRoadTime);

async function saveOrderMeta() {
  try {
    const logId = await ensureTodaysLog();
    await supabase.from('work_logs').update({
      tractor:     tractorInput.value.trim() || null,
      description: descInput.value.trim()    || null,
    }).eq('id', logId);
    saveTractorToHistory(tractorInput.value.trim());
  } catch (e) {
    showFormError('Napaka pri shranjevanju.');
  }
}
tractorInput.addEventListener('blur',  saveOrderMeta);
descInput.addEventListener('blur',     saveOrderMeta);

woStartBtn.addEventListener('click', async () => {
  if (currentDetailWorkOrder.status !== 'Plan') return;
  woStartBtn.disabled = true;
  const { error } = await supabase.rpc('start_work_order', { p_work_order_id: currentDetailWorkOrder.id });
  if (error) { showFormError('Napaka pri prevzemu naloga.'); woStartBtn.disabled = false; return; }
  currentDetailWorkOrder.status    = 'V delu';
  currentDetailWorkOrder.izvajalec = currentUser.id;
  currentDetailWorkOrder.profiles  = { full_name: currentUserName };
  showFormSuccess('✓ Nalog prevzet!');
  updateOrderHeader();
  await loadWorkOrders();
});

// ── Wire buttons ───────────────────────────────────────────────
function wireLogButtons() {
  logsList.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => {
      pendingDeleteId = btn.dataset.id;
      deleteModal.hidden = false;
      document.body.style.overflow = 'hidden';
    });
  });
}

deleteConfirmBtn.addEventListener('click', async () => {
  if (!pendingDeleteId) return;
  deleteConfirmBtn.disabled = true;

  const { error } = await supabase
    .from('work_logs')
    .delete()
    .eq('id', pendingDeleteId)
    .eq('operator_id', currentUser.id);

  deleteConfirmBtn.disabled = false;
  closeDeleteModal();
  if (!error) await loadLogs();
});

deleteCancelBtn.addEventListener('click', closeDeleteModal);

function closeDeleteModal() {
  pendingDeleteId = null;
  deleteModal.hidden = true;
  document.body.style.overflow = '';
}

logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.replace('index.html');
});

// ── FAB menu ───────────────────────────────────────────────────
addBtn.addEventListener('click', (e) => {
  e.stopPropagation();
  fabMenu.hidden = !fabMenu.hidden;
});
fabMenu.addEventListener('click', e => e.stopPropagation());
document.addEventListener('click', () => { fabMenu.hidden = true; });

fabMenu.querySelectorAll('.fab-menu-item').forEach(btn => {
  btn.addEventListener('click', () => {
    fabMenu.hidden = true;
    if (btn.dataset.action === 'new-work-order') openWorkOrderModal();
    if (btn.dataset.action === 'customer-list')  openDeclModal();
  });
});

modalClose.addEventListener('click', closeModal);
cancelBtn.addEventListener('click', closeModal);

formModal.addEventListener('click', e => { if (e.target === formModal) closeModal(); });
deleteModal.addEventListener('click', e => { if (e.target === deleteModal) closeDeleteModal(); });
declModal.addEventListener('click', e => { if (e.target === declModal) closeDeclModal(); });
declModalClose.addEventListener('click', closeDeclModal);

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (!formModal.hidden)      closeModal();
    if (!deleteModal.hidden)    closeDeleteModal();
    if (!workOrderModal.hidden) closeWorkOrderModal();
    if (!declModal.hidden)      closeDeclModal();
  }
});

// ── Tabs ───────────────────────────────────────────────────────
function switchTab(tab) {
  currentTab = tab;
  tabEvidenca.classList.toggle('tab-btn--active', tab === 'evidenca');
  tabNalogi.classList.toggle('tab-btn--active', tab === 'nalogi');
  panelEvidenca.hidden = tab !== 'evidenca';
  panelNalogi.hidden   = tab !== 'nalogi';
  updateFabVisibility();
  if (tab === 'nalogi' && !workOrdersLoaded) loadWorkOrders();
}

function updateFabVisibility() {
  addBtn.hidden = currentRole !== 'admin';
}

tabEvidenca.addEventListener('click', () => switchTab('evidenca'));
tabNalogi.addEventListener('click',   () => switchTab('nalogi'));

// ── Work orders: load + render ───────────────────────────────────
function slugStatus(status) {
  return { 'Plan': 'plan', 'V delu': 'delo', 'Izvedeno': 'izvedeno', 'Izdan Račun': 'racun' }[status] || 'plan';
}

const WO_STATUS_ORDER = { 'Plan': 0, 'V delu': 1, 'Izvedeno': 2, 'Izdan Račun': 3 };
const WO_SORT_COLUMNS = [
  { key: 'stevilka', label: 'Št.' },
  { key: 'stranka',  label: 'Stranka' },
  { key: 'gerki',    label: 'GERKI', center: true },
  { key: 'ha',       label: 'Ha' },
  { key: 'status',   label: 'Status' },
];

let woSortKey = null;   // 'stevilka' | 'stranka' | 'gerki' | 'ha' | 'status'
let woSortDir = 'asc';

function sortWorkOrderRows(rows) {
  if (!woSortKey) return rows;
  const dir = woSortDir === 'asc' ? 1 : -1;
  return [...rows].sort((a, b) => {
    let cmp = 0;
    switch (woSortKey) {
      case 'stevilka': cmp = String(a.stevilka).localeCompare(String(b.stevilka), undefined, { numeric: true }); break;
      case 'stranka':  cmp = a.stranka.localeCompare(b.stranka); break;
      case 'gerki':    cmp = a.gerkCount - b.gerkCount; break;
      case 'ha':       cmp = a.totalHa - b.totalHa; break;
      case 'status':   cmp = (WO_STATUS_ORDER[a.status] ?? 99) - (WO_STATUS_ORDER[b.status] ?? 99); break;
    }
    return cmp * dir;
  });
}

async function loadWorkOrders() {
  workOrdersList.innerHTML = `
    <div class="state-loading">
      <div class="spinner"></div>
      <p>Nalaganje...</p>
    </div>`;

  const [{ data, error }, { data: centerPoints }] = await Promise.all([
    supabase
      .from('delovni_nalogi')
      .select('*, customers(naziv, company_name), profiles(full_name), delovni_nalogi_gerki(id, gerk_code, kolicina_ha, lokacija, delovni_nalogi_vzorci(id, sample_no, sampling_date, sending_date, sampling_note, sending_note, sampling_depth_cm, area_ha))')
      .order('ustvarjen', { ascending: false }),
    // One batched call for every row's map point, instead of one RPC
    // round trip per row — see get_work_orders_center_points.
    supabase.rpc('get_work_orders_center_points'),
  ]);

  if (error) {
    workOrdersList.innerHTML = `<div class="state-empty"><p>Napaka pri nalaganju. Poskusite znova.</p></div>`;
    return;
  }

  workOrderCenterPoints = Object.fromEntries(
    (centerPoints || []).map(p => [p.work_order_id, { lat: p.lat, lng: p.lng }])
  );
  workOrders = data ?? [];
  workOrdersLoaded = true;
  renderWorkOrders();
}

function filteredWorkOrders() {
  const q = woSearchStranka.value.trim().toLowerCase();
  if (!q) return workOrders;
  return workOrders.filter(wo => {
    const stranka = wo.customers?.naziv || wo.customers?.company_name || '';
    return stranka.toLowerCase().includes(q);
  });
}

function renderWorkOrders() {
  const fwo = filteredWorkOrders();

  if (fwo.length === 0) {
    const msg = woSearchStranka.value.trim() ? 'Ni zadetkov za to stranko.' : 'Ni delovnih nalogov.';
    workOrdersList.innerHTML = `<div class="state-empty"><p>${msg}</p></div>`;
    return;
  }

  workOrdersList.className = 'logs-list logs-list--compact';

  const isAdmin = currentRole === 'admin';
  // Maps + confirmed are desktop-only additions (see the 900px+ media
  // query) — modifier classes pick which grid-template-columns applies;
  // the elements themselves render unconditionally (aside from the
  // admin-only checkbox), CSS just doesn't give them room below 900px.
  const rowMod = `wo-compact--enhanced${isAdmin ? ' wo-compact--admin' : ''}`;
  const headMod = `wo-lc-header--enhanced${isAdmin ? ' wo-lc-header--admin' : ''}`;

  const rowData = fwo.map(wo => {
    const gerks = wo.delovni_nalogi_gerki || [];
    const point = workOrderCenterPoints[wo.id];
    return {
      id:        wo.id,
      stevilka:  wo.stevilka,
      stranka:   wo.customers?.naziv || wo.customers?.company_name || '—',
      gerkCount: gerks.length,
      totalHa:   gerks.reduce((s, g) => s + (g.kolicina_ha || 0), 0),
      status:    wo.status,
      lat:       point?.lat ?? null,
      lng:       point?.lng ?? null,
      confirmed: !!wo.confirmed,
    };
  });

  const header = `
    <div class="lc-header wo-lc-header ${headMod}">
      ${WO_SORT_COLUMNS.map(col => {
        const active = woSortKey === col.key;
        const arrow  = active ? (woSortDir === 'asc' ? ' ▲' : ' ▼') : '';
        return `<button type="button" class="wo-th${col.center ? ' wo-th-center' : ''}${active ? ' wo-th--active' : ''}" data-sort="${col.key}">${col.label}${arrow}</button>`;
      }).join('')}
      <span class="wo-th wo-th-center">Zemljevid</span>
      ${isAdmin ? '<span class="wo-th wo-th-center">Potrjeno</span>' : ''}
    </div>`;

  const rows = sortWorkOrderRows(rowData).map(r => {
    const haStr = r.totalHa > 0 ? r.totalHa.toFixed(2) : '—';
    const mapsCell = r.lat != null && r.lng != null
      ? `<a class="wo-c-maps" href="https://www.google.com/maps?q=${r.lat},${r.lng}" target="_blank" rel="noopener" aria-label="Odpri na zemljevidu">📍</a>`
      : `<span class="wo-c-maps wo-c-maps--empty">—</span>`;
    const confirmCell = isAdmin
      ? `<span class="wo-c-confirmed"><input type="checkbox" class="wo-confirm-checkbox" data-id="${escHtml(r.id)}" ${r.confirmed ? 'checked' : ''}></span>`
      : '';
    return `
      <div class="log-compact wo-compact ${rowMod}" role="listitem" data-action="wo-open" data-id="${escHtml(r.id)}">
        <span class="lc-date">${escHtml(r.stevilka)}</span>
        <span class="wo-c-stranka">${escHtml(r.stranka)}</span>
        <span class="wo-c-gerki">${r.gerkCount || '—'}</span>
        <span class="lc-ha">${haStr}</span>
        <span class="wo-status-badge wo-status--${slugStatus(r.status)}">${escHtml(r.status)}</span>
        ${mapsCell}
        ${confirmCell}
      </div>`;
  }).join('');

  workOrdersList.innerHTML = header + rows;
  wireWorkOrderButtons();
}

function wireWorkOrderButtons() {
  workOrdersList.querySelectorAll('[data-action="wo-open"]').forEach(row => {
    row.addEventListener('click', () => {
      const wo = workOrders.find(w => w.id === row.dataset.id);
      if (wo) openWorkOrderDetail(wo);
    });
  });
  // Scoped to <button> — the static Zemljevid/Potrjeno header labels
  // share the .wo-th class purely for visual consistency and aren't
  // sortable (no data-sort), so they're plain <span> elements, not
  // buttons — matching this selector to them would sort by "undefined".
  workOrdersList.querySelectorAll('button.wo-th').forEach(btn => {
    btn.addEventListener('click', () => {
      const key = btn.dataset.sort;
      woSortDir = (woSortKey === key && woSortDir === 'asc') ? 'desc' : 'asc';
      woSortKey = key;
      renderWorkOrders();
    });
  });
  workOrdersList.querySelectorAll('.wo-confirm-checkbox').forEach(cb => {
    cb.addEventListener('click', e => e.stopPropagation()); // don't also open the detail modal
    cb.addEventListener('change', () => updateWorkOrderConfirmed(cb));
  });
}

async function updateWorkOrderConfirmed(cb) {
  const id        = cb.dataset.id;
  const confirmed = cb.checked;
  cb.disabled = true;
  try {
    const { error } = await supabase.from('delovni_nalogi').update({ confirmed }).eq('id', id);
    if (error) throw error;
    const wo = workOrders.find(w => w.id === id);
    if (wo) wo.confirmed = confirmed;
  } catch (e) {
    cb.checked = !confirmed; // revert — the list isn't reloaded on failure
  } finally {
    cb.disabled = false;
  }
}

function getAvailableStranke() {
  const set = new Set();
  workOrders.forEach(wo => {
    const name = wo.customers?.naziv || wo.customers?.company_name;
    if (name) set.add(name);
  });
  return Array.from(set).sort((a, b) => a.localeCompare(b));
}

function showWoSearchSuggestions() {
  const q = woSearchStranka.value.trim().toLowerCase();
  const all = getAvailableStranke();
  const matches = q ? all.filter(n => n.toLowerCase().includes(q)) : all;
  if (!matches.length) { woSearchSuggestions.hidden = true; return; }
  woSearchSuggestions.innerHTML = matches.map(name =>
    `<li class="gerk-suggestion-item" data-name="${escHtml(name)}"><span class="gerk-suggestion-code">${escHtml(name)}</span></li>`
  ).join('');
  woSearchSuggestions.hidden = false;
}

woSearchStranka.addEventListener('input', () => { renderWorkOrders(); showWoSearchSuggestions(); });
woSearchStranka.addEventListener('focus', showWoSearchSuggestions);
woSearchStranka.addEventListener('blur', () => {
  setTimeout(() => { woSearchSuggestions.hidden = true; }, 150);
});
woSearchSuggestions.addEventListener('mousedown', e => {
  const item = e.target.closest('.gerk-suggestion-item');
  if (!item) return;
  woSearchStranka.value = item.dataset.name;
  woSearchSuggestions.hidden = true;
  renderWorkOrders();
});

// ── Work orders: customer + operator lookups ────────────────────
async function loadCustomers() {
  const { data } = await supabase
    .from('customers')
    .select('id, naziv, company_name, contact_name, email')
    .order('naziv');
  customers = (data ?? []).map(c => ({
    id: c.id,
    name: c.naziv || c.company_name || '—',
    contactName: c.contact_name || null,
    email: c.email || null,
  }));
}

async function loadOperatorsList() {
  const { data } = await supabase.from('profiles').select('id, full_name').order('full_name');
  operatorsList = data ?? [];
  woIzvajalecSel.innerHTML = '<option value="">— brez —</option>' +
    operatorsList.map(p => `<option value="${p.id}">${escHtml(p.full_name || '—')}</option>`).join('');
}

function filterCustomers(query) {
  if (!query) return [];
  const q = query.toLowerCase();
  return customers.filter(c => c.name.toLowerCase().includes(q)).slice(0, 8);
}

function showCustomerSuggestions(matches) {
  if (!matches.length) { woStrankaSuggestions.hidden = true; return; }
  woStrankaSuggestions.innerHTML = matches.map(c =>
    `<li class="gerk-suggestion-item" data-id="${c.id}"><span class="gerk-suggestion-code">${escHtml(c.name)}</span></li>`
  ).join('');
  woStrankaSuggestions.hidden = false;
}

woStrankaInput.addEventListener('input', () => {
  woStrankaIdInput.value = '';
  showCustomerSuggestions(filterCustomers(woStrankaInput.value.trim()));
});
woStrankaInput.addEventListener('blur', () => {
  setTimeout(() => { woStrankaSuggestions.hidden = true; }, 150);
});
woStrankaSuggestions.addEventListener('mousedown', e => {
  const item = e.target.closest('.gerk-suggestion-item');
  if (!item) return;
  const c = customers.find(c => c.id === item.dataset.id);
  if (c) {
    woStrankaInput.value = c.name;
    woStrankaIdInput.value = c.id;
  }
  woStrankaSuggestions.hidden = true;
});

// ── Seznam strank modal: open/close + list view ──────────────────
async function openDeclModal() {
  if (!customers.length) await loadCustomers();
  declModal.hidden = false;
  showDeclList();
}

function closeDeclModal() {
  declModal.hidden = true;
}

function showDeclList() {
  declListView.hidden = false;
  declDetailView.hidden = true;
  declListSearch.value = '';
  renderDeclCustomerList();
}

function renderDeclCustomerList() {
  const q = declListSearch.value.trim().toLowerCase();
  const matches = q ? customers.filter(c => c.name.toLowerCase().includes(q)) : customers;

  if (!matches.length) {
    declCustomerList.innerHTML = `<div class="state-empty"><p>Ni strank.</p></div>`;
    return;
  }

  declCustomerList.innerHTML = matches.map(c =>
    `<div class="decl-customer-row" data-id="${c.id}">${escHtml(c.name)}</div>`
  ).join('');

  declCustomerList.querySelectorAll('.decl-customer-row').forEach(row => {
    row.addEventListener('click', () => openDeclDetail(row.dataset.id));
  });
}

declListSearch.addEventListener('input', renderDeclCustomerList);
declBackBtn.addEventListener('click', showDeclList);

// ── Seznam strank modal: one customer's detail view ──────────────
function openDeclDetail(customerId) {
  const customer = customers.find(c => c.id === customerId);
  if (!customer) return;

  declCustomerId = customerId;
  declListView.hidden = true;
  declDetailView.hidden = false;
  declLinkResult.hidden = true;

  const sub = [customer.contactName, customer.email].filter(Boolean).join(' · ');
  declCustomerInfo.innerHTML = `
    <p class="wo-order-label">${escHtml(customer.name)}</p>
    ${sub ? `<p class="decl-link-sub">${escHtml(sub)}</p>` : ''}`;

  loadDeclCustomerLinks();
  loadDeclCustomerTable();
}

// ── Seznam strank modal: generate a customer link ────────────────
declGenerateBtn.addEventListener('click', async () => {
  if (!declCustomerId) return;
  const year = new Date().getFullYear();

  declGenerateBtn.disabled = true;
  const { data: token, error } = await supabase.rpc('create_field_declaration_link', {
    p_customer_id: declCustomerId,
    p_year: year,
  });
  declGenerateBtn.disabled = false;

  if (error) {
    declLinkResult.innerHTML = `<div class="alert alert-error">Napaka: ${escHtml(error.message)}</div>`;
    declLinkResult.hidden = false;
    return;
  }

  const url = new URL('deklaracija.html', location.href);
  url.searchParams.set('token', token);
  const customer = customers.find(c => c.id === declCustomerId);
  declLinkResult.innerHTML = `
    <div class="alert alert-success">
      Povezava ustvarjena.
      <button type="button" class="btn btn-secondary btn-sm" id="declCopyNewBtn">Kopiraj povezavo</button>
      ${customer?.email ? `<button type="button" class="btn btn-secondary btn-sm" id="declSendNewBtn" data-token="${token}">Pošlji e-pošto</button>` : ''}
    </div>`;
  declLinkResult.hidden = false;
  document.getElementById('declCopyNewBtn').addEventListener('click', () => navigator.clipboard.writeText(url.toString()));
  const sendNewBtn = document.getElementById('declSendNewBtn');
  if (sendNewBtn) wireSendEmailButton(sendNewBtn);
  loadDeclCustomerLinks();
});

// ── Deklaracije tab: send/resend the declaration email ───────────
function wireSendEmailButton(btn) {
  btn.addEventListener('click', async () => {
    const token = btn.dataset.token;
    btn.disabled = true;
    btn.textContent = 'Pošiljanje...';

    const { error } = await supabase.rpc('send_field_declaration_email', { p_token: token });

    if (error) {
      btn.title = `Napaka pri pošiljanju: ${error.message}`;
      btn.textContent = 'Napaka — poskusi znova';
      btn.disabled = false;
    } else {
      loadDeclCustomerLinks();
    }
  });
}

// ── Deklaracije tab: existing links list ─────────────────────────
async function loadDeclCustomerLinks() {
  const { data, error } = await supabase
    .from('customer_links')
    .select('*')
    .eq('customer_id', declCustomerId)
    .eq('purpose', 'field_declarations')
    .order('created_at', { ascending: false });

  if (error) { declLinksList.innerHTML = `<p class="state-empty-inline">Napaka pri nalaganju povezav.</p>`; return; }
  renderDeclLinks(data ?? []);
}

function renderDeclLinks(links) {
  if (!links.length) {
    declLinksList.innerHTML = `<p class="state-empty-inline">Za to stranko še ni ustvarjenih povezav.</p>`;
    return;
  }

  const customer = customers.find(c => c.id === declCustomerId);

  declLinksList.innerHTML = links.map(l => {
    const url = new URL('deklaracija.html', location.href);
    url.searchParams.set('token', l.token);
    const expired = l.expires_at && new Date(l.expires_at) < new Date();
    const created = new Date(l.created_at).toLocaleDateString('sl-SI');
    const lastUsed = l.last_used_at ? new Date(l.last_used_at).toLocaleDateString('sl-SI') : null;
    const emailSent = l.email_sent_at ? new Date(l.email_sent_at).toLocaleDateString('sl-SI') : null;

    return `
      <div class="decl-link-row">
        <div class="decl-link-meta">
          <strong>${l.year}</strong> · ${l.lang.toUpperCase()}
          ${expired ? '<span class="wo-status-badge wo-status--plan">Poteklo</span>' : ''}
          <div class="decl-link-sub">
            Ustvarjeno: ${created}${lastUsed ? ' · Zadnja uporaba: ' + lastUsed : ' · še ni uporabljeno'}
            ${emailSent ? ' · E-pošta poslana: ' + emailSent : ' · E-pošta še ni poslana'}
          </div>
        </div>
        <div class="decl-link-actions">
          <button type="button" class="btn btn-secondary btn-sm" data-copy="${escHtml(url.toString())}">Kopiraj</button>
          ${customer?.email ? `<button type="button" class="btn btn-secondary btn-sm decl-send-btn" data-token="${l.token}">${emailSent ? 'Pošlji ponovno' : 'Pošlji e-pošto'}</button>` : ''}
        </div>
      </div>`;
  }).join('');

  declLinksList.querySelectorAll('.decl-send-btn').forEach(wireSendEmailButton);

  declLinksList.querySelectorAll('[data-copy]').forEach(btn => {
    btn.addEventListener('click', () => navigator.clipboard.writeText(btn.dataset.copy));
  });
}

// ── Deklaracije tab: review table ────────────────────────────────
async function loadDeclCustomerTable() {
  const year = new Date().getFullYear();
  declTableWrap.innerHTML = `<div class="state-loading"><div class="spinner"></div><p>Nalaganje...</p></div>`;

  const [{ data: flds, error: fErr }, { data: decls, error: dErr }] = await Promise.all([
    supabase.from('fields').select('id, name, area_ha, cadastre_id').eq('customer_id', declCustomerId).order('name'),
    supabase.from('field_declarations').select('*').eq('customer_id', declCustomerId).eq('year', year),
  ]);

  if (fErr || dErr) { declTableWrap.innerHTML = `<div class="state-empty"><p>Napaka pri nalaganju.</p></div>`; return; }

  const byField = new Map((decls ?? []).map(d => [d.field_id, d]));
  const rows = (flds ?? []).map(f => ({ ...f, decl: byField.get(f.id) || null }));
  renderDeclTable(rows, year);
}

function renderDeclTable(rows, year) {
  if (!rows.length) {
    declTableWrap.innerHTML = `<p class="state-empty-inline">Ta stranka nima evidentiranih polj.</p>`;
    return;
  }

  const yn = (v) => (v === true ? 'Da' : v === false ? 'Ne' : '—');
  const body = rows.map(f => {
    const d = f.decl;
    const kolicina = d?.organic_fertilizer_amount != null
      ? `${d.organic_fertilizer_amount}${d.organic_fertilizer_unit ? ' ' + d.organic_fertilizer_unit : ''}`
      : '—';
    return `
      <tr>
        <td>${escHtml(f.name)}</td>
        <td>${escHtml(f.cadastre_id || '—')}</td>
        <td>${f.area_ha ?? '—'}</td>
        <td>${escHtml(d?.crop_current || '—')}</td>
        <td>${escHtml(d?.crop_next || '—')}</td>
        <td>${yn(d?.green_cover)}</td>
        <td>${yn(d?.straw_stays)}</td>
        <td>${d?.expected_yield_t_per_ha ?? '—'}</td>
        <td>${yn(d?.organic_fertilizer_used)}</td>
        <td>${escHtml(d?.organic_fertilizer_type || '—')}</td>
        <td>${kolicina}</td>
      </tr>`;
  }).join('');

  declTableWrap.innerHTML = `
    <div class="decl-table-scroll">
      <table class="decl-table">
        <thead>
          <tr>
            <th>Polje</th><th>GERK</th><th>Ha</th>
            <th>Kultura ${year}</th><th>Kultura ${year + 1}</th>
            <th>Zel. gnojidba</th><th>Slama ostane</th><th>Prid. (t/ha)</th>
            <th>Org. gnojilo</th><th>Tip</th><th>Količina</th>
          </tr>
        </thead>
        <tbody>${body}</tbody>
      </table>
    </div>`;
}

// ── Work order modal (create only — there is no edit entry point) ──
async function openWorkOrderModal() {
  woModalTitle.textContent = 'Nov delovni nalog';
  workOrderForm.reset();
  woStrankaIdInput.value = '';
  hideWoFormFeedback();
  woStatusSel.value = 'Plan';
  woGerksListEl.innerHTML = '';
  woStevilkaLabel.textContent = 'Številka bo dodeljena samodejno ob shranjevanju';

  if (!customers.length) await loadCustomers();
  if (!operatorsList.length) await loadOperatorsList();

  addGerkRow(woGerksListEl);

  workOrderModal.hidden = false;
  document.body.style.overflow = 'hidden';
}

function closeWorkOrderModal() {
  workOrderModal.hidden = true;
  document.body.style.overflow = '';
}

function hideWoFormFeedback() {
  woFormError.hidden   = true;
  woFormSuccess.hidden = true;
}

function showWoFormError(msg) {
  woFormError.textContent = msg;
  woFormError.hidden = false;
  woFormSuccess.hidden = true;
}

function showWoFormSuccess(msg) {
  woFormSuccess.textContent = msg;
  woFormSuccess.hidden = false;
  woFormError.hidden = true;
}

function setWoSaveLoading(on) {
  woSaveBtn.disabled   = on;
  woCancelBtn.disabled = on;
  woSaveBtn.querySelector('.btn-label').hidden   = on;
  woSaveBtn.querySelector('.btn-spinner').hidden = !on;
}

woAddGerkBtn.addEventListener('click', () => {
  const input = addGerkRow(woGerksListEl);
  input.focus();
});

workOrderForm.addEventListener('submit', async e => {
  e.preventDefault();
  hideWoFormFeedback();

  const gerkRows = getFormGerks(woGerksListEl);

  if (!gerkRows.length) return showWoFormError('Dodajte vsaj en GERK.');

  for (const g of gerkRows) {
    const known = fields.find(f => f.code === g.code);
    if (!known && !/^\d{7}$/.test(g.code))
      return showWoFormError(`Neveljaven GERK: "${g.code}" (mora biti 7-mestna številka).`);
  }

  setWoSaveLoading(true);

  const payload = {
    stranka_id:    woStrankaIdInput.value || null,
    izvajalec:     woIzvajalecSel.value || null,
    tip_storitve:  woTipSel.value || null,
    strosek_ocena: woStrosekOcenaInput.value ? parseFloat(woStrosekOcenaInput.value) : null,
    strosek:       woStrosekInput.value ? parseFloat(woStrosekInput.value) : null,
    status:        woStatusSel.value,
    podrobnosti:   woPodrobnostiInput.value.trim() || null,
  };

  const { data, error: saveError } = await supabase.from('delovni_nalogi').insert(payload).select('id').single();
  const workOrderId = data?.id;

  if (saveError) {
    setWoSaveLoading(false);
    showWoFormError('Napaka pri shranjevanju. Preverite podatke in poskusite znova.');
    return;
  }

  const { error: gerkError } = await supabase
    .from('delovni_nalogi_gerki')
    .insert(gerkRows.map(g => ({
      delovni_nalog_id: workOrderId,
      gerk_code:        g.code,
      kolicina_ha:      g.hectares,
      lokacija:         g.lokacija,
    })));

  setWoSaveLoading(false);

  if (gerkError) {
    showWoFormError('Napaka pri shranjevanju GERKOV.');
    return;
  }

  showWoFormSuccess('✓ Nalog shranjen!');
  await loadWorkOrders();
  setTimeout(closeWorkOrderModal, 1000);
});

woModalClose.addEventListener('click', closeWorkOrderModal);
woCancelBtn.addEventListener('click', closeWorkOrderModal);
workOrderModal.addEventListener('click', e => { if (e.target === workOrderModal) closeWorkOrderModal(); });

// ── Boot ───────────────────────────────────────────────────────
async function boot() {
  const authed = await initAuth();
  if (!authed) return;

  buildTimeOptions();
  renderMonthLabel();
  loadFields();

  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name, role, organization')
    .eq('id', currentUser.id)
    .maybeSingle();

  const displayName = profile?.full_name ?? currentUser.email;
  currentRole = profile?.role ?? 'operator';
  currentOrg  = profile?.organization ?? null;
  currentUserName = displayName;
  operatorNameEl.textContent = displayName;
  if (currentRole === 'admin') {
    adminBadge.textContent = 'Admin';
    adminBadge.hidden = false;
  } else if (currentRole === 'supervisor') {
    adminBadge.textContent = 'Nadzornik';
    adminBadge.hidden = false;
  } else {
    adminBadge.hidden = true;
  }
  renderGreeting(displayName);
  updateFabVisibility();

  // Delovni Nalogi is the default visible tab now — load it first so the
  // user isn't staring at a spinner; Evidenca dela loads in the background
  // so switching to it later is instant.
  await loadWorkOrders();
  loadLogs();
}

boot();
