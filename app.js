import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

// Bump alongside sw.js's CACHE constant on every push to GitHub.
const APP_VERSION = 'v1.2';

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
let pendingDeleteType = 'log'; // 'log' | 'workorder'
let viewMode     = 'compact';
let currentMonth = new Date().toISOString().slice(0, 7);

let currentTab       = 'nalogi'; // 'evidenca' | 'nalogi'
let workOrders       = [];
let workOrdersLoaded = false;
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
const woStartBtn  = document.getElementById('woStartBtn');
const woHeaderMeta = document.getElementById('woHeaderMeta');
const roadHourSel = document.getElementById('roadHour');
const roadMinSel  = document.getElementById('roadMin');
const workLogGerkRowsEl = document.getElementById('workLogGerkRows');
const tractorInput = document.getElementById('tractor');
const descInput   = document.getElementById('description');
const formError   = document.getElementById('formError');
const formSuccess = document.getElementById('formSuccess');
const cancelBtn   = document.getElementById('cancelBtn');

const deleteModal      = document.getElementById('deleteModal');
const deleteTitleEl    = document.getElementById('deleteTitle');
const deleteBodyEl     = document.getElementById('deleteBody');
const deleteCancelBtn  = document.getElementById('deleteCancelBtn');
const deleteConfirmBtn = document.getElementById('deleteConfirmBtn');

// ── Tabs ───────────────────────────────────────────────────────
const tabEvidenca   = document.getElementById('tabEvidenca');
const tabNalogi     = document.getElementById('tabNalogi');
const panelEvidenca = document.getElementById('panelEvidenca');
const panelNalogi   = document.getElementById('panelNalogi');
const workOrdersList = document.getElementById('workOrdersList');

// ── Work order modal refs ───────────────────────────────────────
const workOrderModal      = document.getElementById('workOrderModal');
const woModalTitle        = document.getElementById('woModalTitle');
const woModalClose        = document.getElementById('woModalClose');
const workOrderForm       = document.getElementById('workOrderForm');
const woEditIdInput       = document.getElementById('woEditId');
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

function setDurationSels(hourSel, minSel, totalMins) {
  const mins = totalMins || 0;
  hourSel.value = String(Math.floor(mins / 60));
  minSel.value  = String(mins % 60).padStart(2, '0');
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
async function loadFields() {
  const { data } = await supabase
    .from('FIELD')
    .select('CODE, NAME, TOTAL_AREA, B_FIELD_X_CUSTOMER(DATE_TO, CUSTOMER(FULL_NAME))')
    .order('NAME');
  const seen = new Set();
  fields = (data ?? [])
    .filter(f => f.CODE)
    .map(f => {
      const activeLink = (f.B_FIELD_X_CUSTOMER ?? [])
        .find(l => !l.DATE_TO || new Date(l.DATE_TO) >= new Date());
      return {
        code:     f.CODE,
        name:     f.NAME ?? null,
        area:     f.TOTAL_AREA ?? null,
        customer: activeLink?.CUSTOMER?.FULL_NAME ?? null,
      };
    })
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
function buildGerkPlanRows(workOrder, todaysGerks) {
  const planFields = workOrder?.delovni_nalogi_gerki || [];
  const logByCode   = Object.fromEntries((todaysGerks || []).map(g => [g.gerk_code, g]));

  const rows = planFields.map(pf => ({
    code:      pf.gerk_code,
    hectares:  pf.kolicina_ha ?? logByCode[pf.gerk_code]?.hectares ?? null,
    lokacija:  pf.lokacija ?? null,
    startTime: logByCode[pf.gerk_code]?.start_time ?? null,
    endTime:   logByCode[pf.gerk_code]?.end_time ?? null,
    duration:  logByCode[pf.gerk_code]?.duration ?? null,
    completed: logByCode[pf.gerk_code]?.completed ?? false,
  }));

  const planCodes = new Set(planFields.map(pf => pf.gerk_code));
  (todaysGerks || []).filter(g => !planCodes.has(g.gerk_code)).forEach(g => {
    rows.push({
      code: g.gerk_code, hectares: g.hectares, lokacija: null,
      startTime: g.start_time, endTime: g.end_time, duration: g.duration ?? null, completed: g.completed ?? false,
    });
  });

  return rows;
}

function fmtHM(mins) {
  if (!mins) return '0m';
  const h = Math.floor(mins / 60), m = mins % 60;
  return m ? `${h}h ${m}m` : `${h}h`;
}

function fmtHMS(totalSeconds) {
  const s  = Math.max(0, totalSeconds);
  const hh = Math.floor(s / 3600);
  const mm = Math.floor((s % 3600) / 60);
  const ss = Math.floor(s % 60);
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
}

// ── Live per-row ticking timers (mm:ss while running) ───────────
const activeTickers = new Map(); // gerk_code -> intervalId

function startRowTicker(row) {
  stopRowTicker(row);
  const timerEl = row.querySelector('.wlg-timer');
  const tick = () => {
    const startMs = new Date(row.dataset.start).getTime();
    timerEl.textContent = fmtHMS(Math.floor((Date.now() - startMs) / 1000));
  };
  tick();
  activeTickers.set(row.dataset.code, setInterval(tick, 1000));
}

function stopRowTicker(row) {
  const id = activeTickers.get(row.dataset.code);
  if (id) { clearInterval(id); activeTickers.delete(row.dataset.code); }
}

function stopAllTickers() {
  activeTickers.forEach(id => clearInterval(id));
  activeTickers.clear();
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
    const running   = !!(r.startTime && !r.endTime);
    const completed = !!(r.endTime);
    return `
      <div class="wlg-row${completed ? ' wlg-row--completed' : ''}" data-code="${escHtml(r.code)}" data-hectares="${r.hectares ?? ''}"
           data-start="${r.startTime || ''}" data-end="${r.endTime || ''}" data-duration="${r.duration ?? ''}">
        <div class="wlg-info">
          <span class="wlg-code-line"><span class="wlg-code">${escHtml(r.code)}</span>${name ? ` <span class="wlg-name">${escHtml(name)}</span>` : ''}</span>
          ${meta ? `<span class="wlg-meta">${escHtml(meta)}</span>` : ''}
        </div>
        <span class="wlg-timer" ${running ? '' : 'hidden'}></span>
        <input type="text" class="field-input wlg-duration-input" placeholder="hh:mm:ss" inputmode="numeric"
               value="${r.duration != null ? fmtHMS(r.duration) : ''}" ${completed ? '' : 'hidden'}>
        <button type="button" class="wlg-toggle-btn${running ? ' wlg-toggle-btn--running' : ''}" data-action="wlg-toggle">${running ? 'Stop' : 'Start'}</button>
      </div>`;
  }).join('');

  workLogGerkRowsEl.querySelectorAll('.wlg-row').forEach(row => {
    if (row.dataset.start && !row.dataset.end) startRowTicker(row);
  });

  wireGerkRowButtons();
}

function updateOrderHeader() {
  const wo = currentDetailWorkOrder;
  const rows = Array.from(workLogGerkRowsEl.querySelectorAll('.wlg-row'));
  const allCompleted = rows.length > 0 && rows.every(r => r.classList.contains('wlg-row--completed'));
  const totalSec = rows.reduce((s, r) => s + (parseInt(r.dataset.duration, 10) || 0), 0);
  const totalMin = Math.round(totalSec / 60);

  woStartBtn.classList.toggle('btn-started', wo.status !== 'Plan');
  if (wo.status === 'Plan') {
    woStartBtn.textContent = 'Start';
    woStartBtn.disabled = false;
  } else {
    woStartBtn.textContent = allCompleted ? 'Končan' : 'V delu';
    woStartBtn.disabled = true;
  }

  const opName = wo.profiles?.full_name;
  const metaParts = [];
  if (wo.status !== 'Plan' && opName) metaParts.push(`Izvaja: ${opName}`);
  if (totalMin > 0) metaParts.push(`Skupaj: ${fmtHM(totalMin)}`);
  woHeaderMeta.textContent = metaParts.join(' · ');
}

// ── Modal ──────────────────────────────────────────────────────
let currentDetailWorkOrder = null;
let currentDetailLogId     = null;

async function openWorkOrderDetail(workOrder) {
  currentDetailWorkOrder  = workOrder;
  currentDetailLogId      = null;
  ensureTodaysLogPromise  = null;
  stopAllTickers();

  modalTitle.textContent = 'Delovni nalog';
  hideFormFeedback();
  roadHourSel.value = '0'; roadMinSel.value = '00';
  tractorInput.value = '';
  descInput.value = '';
  updateTractorDatalist();

  const stranka = workOrder.customers?.naziv || workOrder.customers?.company_name;
  workLogOrderLabel.textContent = [workOrder.stevilka, stranka].filter(Boolean).join(' — ');

  const { data: existingLog } = await supabase
    .from('work_logs')
    .select('id, road_duration, tractor, description, work_log_gerks(gerk_code, hectares, start_time, end_time, duration, completed)')
    .eq('operator_id', currentUser.id)
    .eq('work_order_id', workOrder.id)
    .eq('work_date', todayISO())
    .maybeSingle();

  if (existingLog) {
    currentDetailLogId = existingLog.id;
    setDurationSels(roadHourSel, roadMinSel, existingLog.road_duration);
    tractorInput.value = existingLog.tractor || '';
    descInput.value    = existingLog.description || '';
  }

  renderWorkLogGerkRows(buildGerkPlanRows(workOrder, existingLog?.work_log_gerks || []));
  updateOrderHeader();

  formModal.hidden = false;
  document.body.style.overflow = 'hidden';
}

function closeModal() {
  stopAllTickers();
  formModal.hidden = true;
  document.body.style.overflow = '';
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
let ensureTodaysLogPromise = null;

async function ensureTodaysLog() {
  if (currentDetailLogId) return currentDetailLogId;
  // Two GERK rows started in quick succession would otherwise both race
  // through the check-then-insert below before either resolves — share
  // the same in-flight promise so only one insert is ever attempted.
  if (ensureTodaysLogPromise) return ensureTodaysLogPromise;

  ensureTodaysLogPromise = (async () => {
    const today = todayISO();
    const { data: existing } = await supabase
      .from('work_logs')
      .select('id')
      .eq('operator_id', currentUser.id)
      .eq('work_order_id', currentDetailWorkOrder.id)
      .eq('work_date', today)
      .maybeSingle();

    if (existing) { currentDetailLogId = existing.id; return existing.id; }

    const { data, error } = await supabase
      .from('work_logs')
      .insert({ operator_id: currentUser.id, work_order_id: currentDetailWorkOrder.id, work_date: today, work_duration: 0 })
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
          .eq('work_date', today)
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

async function ensureGerkRow(logId, gerkCode, hectares) {
  const { data: existing } = await supabase
    .from('work_log_gerks')
    .select('id, start_time, end_time, duration, completed')
    .eq('work_log_id', logId)
    .eq('gerk_code', gerkCode)
    .maybeSingle();
  if (existing) return existing;

  const { data, error } = await supabase
    .from('work_log_gerks')
    .insert({ work_log_id: logId, gerk_code: gerkCode, hectares })
    .select('id, start_time, end_time, duration, completed')
    .single();
  if (error) throw error;
  return data;
}

async function recomputeWorkLogDuration(logId) {
  const { data } = await supabase.from('work_log_gerks').select('duration').eq('work_log_id', logId);
  const totalSec = (data ?? []).reduce((s, g) => s + (g.duration || 0), 0);
  // work_log_gerks.duration is seconds; work_logs.work_duration stays in
  // minutes since existing stats rendering (updateStats(), fmtDuration()) expects that.
  await supabase.from('work_logs').update({ work_duration: Math.round(totalSec / 60) }).eq('id', logId);
}

async function toggleGerkTimer(btn) {
  const row      = btn.closest('.wlg-row');
  const code     = row.dataset.code;
  const hectares = row.dataset.hectares !== '' ? parseFloat(row.dataset.hectares) : null;
  const durationInput = row.querySelector('.wlg-duration-input');
  const timerEl        = row.querySelector('.wlg-timer');

  btn.disabled = true;
  try {
    const logId   = await ensureTodaysLog();
    const gerkRow = await ensureGerkRow(logId, code, hectares);
    const running = gerkRow.start_time && !gerkRow.end_time;

    let updated;
    if (running) {
      const endIso      = new Date().toISOString();
      const durationSec = Math.max(0, Math.round((new Date(endIso) - new Date(gerkRow.start_time)) / 1000));
      const { data, error } = await supabase
        .from('work_log_gerks')
        .update({ end_time: endIso, duration: durationSec, completed: true })
        .eq('id', gerkRow.id)
        .select('id, start_time, end_time, duration, completed')
        .single();
      if (error) throw error;
      updated = data;
      await recomputeWorkLogDuration(logId);
    } else {
      // (Re)starting always clears any previous end_time/duration/completed
      // state — this is the escape hatch for redoing a field's work, and
      // keeps the header total from double-counting a stale prior session.
      const { data, error } = await supabase
        .from('work_log_gerks')
        .update({ start_time: new Date().toISOString(), end_time: null, duration: null, completed: false })
        .eq('id', gerkRow.id)
        .select('id, start_time, end_time, duration, completed')
        .single();
      if (error) throw error;
      updated = data;
      await recomputeWorkLogDuration(logId);
    }

    row.dataset.start    = updated.start_time || '';
    row.dataset.end      = updated.end_time || '';
    row.dataset.duration = updated.duration ?? '';
    const nowRunning = updated.start_time && !updated.end_time;
    row.classList.toggle('wlg-row--completed', !!updated.end_time);
    btn.textContent = nowRunning ? 'Stop' : 'Start';
    btn.classList.toggle('wlg-toggle-btn--running', nowRunning);

    if (nowRunning) {
      durationInput.hidden = true;
      timerEl.hidden = false;
      startRowTicker(row);
    } else {
      stopRowTicker(row);
      timerEl.hidden = true;
      durationInput.value = updated.duration != null ? fmtHMS(updated.duration) : '';
      durationInput.hidden = false;
    }

    updateOrderHeader();
  } catch (e) {
    showFormError('Napaka pri shranjevanju časa.');
  } finally {
    btn.disabled = false;
  }
}

function parseHMS(text) {
  const parts = text.trim().split(':').map(p => Math.max(0, parseInt(p, 10) || 0));
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0] * 60; // bare number: treat as minutes
  return 0;
}

async function saveGerkDuration(input) {
  const row      = input.closest('.wlg-row');
  const code     = row.dataset.code;
  const hectares = row.dataset.hectares !== '' ? parseFloat(row.dataset.hectares) : null;
  const seconds  = input.value ? parseHMS(input.value) : 0;

  input.disabled = true;
  try {
    const logId   = await ensureTodaysLog();
    const gerkRow = await ensureGerkRow(logId, code, hectares);
    await supabase.from('work_log_gerks').update({ duration: seconds }).eq('id', gerkRow.id);
    row.dataset.duration = seconds;
    input.value = fmtHMS(seconds);
    await recomputeWorkLogDuration(logId);
    updateOrderHeader();
  } catch (e) {
    showFormError('Napaka pri shranjevanju.');
  } finally {
    input.disabled = false;
  }
}

function wireGerkRowButtons() {
  workLogGerkRowsEl.querySelectorAll('[data-action="wlg-toggle"]').forEach(btn => {
    btn.addEventListener('click', () => toggleGerkTimer(btn));
  });
  workLogGerkRowsEl.querySelectorAll('.wlg-duration-input').forEach(input => {
    input.addEventListener('blur', () => saveGerkDuration(input));
  });
}

async function saveOrderMeta() {
  try {
    const logId = await ensureTodaysLog();
    await supabase.from('work_logs').update({
      road_duration: getDurationMins(roadHourSel, roadMinSel) || null,
      tractor:       tractorInput.value.trim() || null,
      description:   descInput.value.trim()    || null,
    }).eq('id', logId);
    saveTractorToHistory(tractorInput.value.trim());
  } catch (e) {
    showFormError('Napaka pri shranjevanju.');
  }
}

roadHourSel.addEventListener('change', saveOrderMeta);
roadMinSel.addEventListener('change',  saveOrderMeta);
tractorInput.addEventListener('blur',  saveOrderMeta);
descInput.addEventListener('blur',     saveOrderMeta);

woStartBtn.addEventListener('click', async () => {
  if (currentDetailWorkOrder.status !== 'Plan') return;
  woStartBtn.disabled = true;
  const { error } = await supabase.rpc('start_work_order', { p_work_order_id: currentDetailWorkOrder.id });
  if (error) { showFormError('Napaka pri zagonu naloga.'); woStartBtn.disabled = false; return; }
  currentDetailWorkOrder.status    = 'V delu';
  currentDetailWorkOrder.izvajalec = currentUser.id;
  currentDetailWorkOrder.profiles  = { full_name: currentUserName };
  showFormSuccess('✓ Nalog zagnan!');
  updateOrderHeader();
  await loadWorkOrders();
});

// ── Wire buttons ───────────────────────────────────────────────
function wireLogButtons() {
  logsList.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => {
      pendingDeleteId   = btn.dataset.id;
      pendingDeleteType = 'log';
      deleteTitleEl.textContent = 'Izbriši vpis?';
      deleteBodyEl.textContent  = 'To dejanje je trajno in ga ni mogoče razveljaviti.';
      deleteModal.hidden = false;
      document.body.style.overflow = 'hidden';
    });
  });
}

deleteConfirmBtn.addEventListener('click', async () => {
  if (!pendingDeleteId) return;
  deleteConfirmBtn.disabled = true;

  const { error } = pendingDeleteType === 'workorder'
    ? await supabase.from('delovni_nalogi').delete().eq('id', pendingDeleteId)
    : await supabase.from('work_logs').delete().eq('id', pendingDeleteId).eq('operator_id', currentUser.id);

  deleteConfirmBtn.disabled = false;
  const type = pendingDeleteType;
  closeDeleteModal();
  if (!error) {
    if (type === 'workorder') await loadWorkOrders();
    else await loadLogs();
  }
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

addBtn.addEventListener('click', () => openWorkOrderModal('Nov delovni nalog'));
modalClose.addEventListener('click', closeModal);
cancelBtn.addEventListener('click', closeModal);

formModal.addEventListener('click', e => { if (e.target === formModal) closeModal(); });
deleteModal.addEventListener('click', e => { if (e.target === deleteModal) closeDeleteModal(); });

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (!formModal.hidden)      closeModal();
    if (!deleteModal.hidden)    closeDeleteModal();
    if (!workOrderModal.hidden) closeWorkOrderModal();
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
  addBtn.hidden = !(currentTab === 'nalogi' && currentRole === 'admin');
}

tabEvidenca.addEventListener('click', () => switchTab('evidenca'));
tabNalogi.addEventListener('click',   () => switchTab('nalogi'));

// ── Work orders: load + render ───────────────────────────────────
function slugStatus(status) {
  return { 'Plan': 'plan', 'V delu': 'delo', 'Izvedeno': 'izvedeno', 'Izdan Račun': 'racun' }[status] || 'plan';
}

async function loadWorkOrders() {
  workOrdersList.innerHTML = `
    <div class="state-loading">
      <div class="spinner"></div>
      <p>Nalaganje...</p>
    </div>`;

  const { data, error } = await supabase
    .from('delovni_nalogi')
    .select('*, customers(naziv, company_name), profiles(full_name), delovni_nalogi_gerki(gerk_code, kolicina_ha, lokacija)')
    .order('ustvarjen', { ascending: false });

  if (error) {
    workOrdersList.innerHTML = `<div class="state-empty"><p>Napaka pri nalaganju. Poskusite znova.</p></div>`;
    return;
  }

  workOrders = data ?? [];
  workOrdersLoaded = true;
  renderWorkOrders();
}

function renderWorkOrders() {
  if (workOrders.length === 0) {
    workOrdersList.innerHTML = `<div class="state-empty"><p>Ni delovnih nalogov.</p></div>`;
    return;
  }

  const canEdit = currentRole === 'admin';

  workOrdersList.className = 'logs-list logs-list--compact';
  const header = `
    <div class="lc-header wo-lc-header" aria-hidden="true">
      <span>Št.</span>
      <span>Stranka</span>
      <span>GERKI</span>
      <span>Ha</span>
      <span>Status</span>
      <span></span>
    </div>`;

  const rows = workOrders.map(wo => {
    const gerks   = wo.delovni_nalogi_gerki || [];
    const totalHa = gerks.reduce((s, g) => s + (g.kolicina_ha || 0), 0);
    const haStr   = totalHa > 0 ? totalHa.toFixed(2) : '—';
    const stranka = wo.customers?.naziv || wo.customers?.company_name || '—';

    return `
      <div class="log-compact wo-compact" role="listitem" data-action="wo-open" data-id="${wo.id}">
        <span class="lc-date">${escHtml(wo.stevilka)}</span>
        <span class="wo-c-stranka">${escHtml(stranka)}</span>
        <span class="wo-c-gerki">${gerks.length || '—'}</span>
        <span class="lc-ha">${haStr}</span>
        <span class="wo-status-badge wo-status--${slugStatus(wo.status)}">${escHtml(wo.status)}</span>
        <div class="lc-actions">
          ${canEdit ? `
          <button class="lc-btn lc-btn--danger" data-action="wo-delete" data-id="${wo.id}" title="Izbriši">${DEL_ICON}</button>` : ''}
        </div>
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
  workOrdersList.querySelectorAll('[data-action="wo-delete"]').forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      pendingDeleteId   = btn.dataset.id;
      pendingDeleteType = 'workorder';
      deleteTitleEl.textContent = 'Izbriši delovni nalog?';
      deleteBodyEl.textContent  = 'To dejanje je trajno in ga ni mogoče razveljaviti.';
      deleteModal.hidden = false;
      document.body.style.overflow = 'hidden';
    });
  });
}

// ── Work orders: customer + operator lookups ────────────────────
async function loadCustomers() {
  const { data } = await supabase
    .from('customers')
    .select('id, naziv, company_name')
    .order('naziv');
  customers = (data ?? []).map(c => ({ id: c.id, name: c.naziv || c.company_name || '—' }));
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

// ── Work order modal ────────────────────────────────────────────
async function openWorkOrderModal(title, prefill = null) {
  woModalTitle.textContent = title;
  workOrderForm.reset();
  woEditIdInput.value = '';
  woStrankaIdInput.value = '';
  hideWoFormFeedback();
  woStatusSel.value = 'Plan';
  woGerksListEl.innerHTML = '';

  if (!customers.length) await loadCustomers();
  if (!operatorsList.length) await loadOperatorsList();

  if (prefill) {
    woEditIdInput.value      = prefill.id;
    woStevilkaLabel.textContent = prefill.stevilka;
    woStrankaIdInput.value   = prefill.stranka_id || '';
    woStrankaInput.value     = prefill.customers?.naziv || prefill.customers?.company_name || '';
    woIzvajalecSel.value     = prefill.izvajalec || '';
    woTipSel.value           = prefill.tip_storitve || '';
    woStrosekOcenaInput.value = prefill.strosek_ocena ?? '';
    woStrosekInput.value     = prefill.strosek ?? '';
    woStatusSel.value        = prefill.status || 'Plan';
    woPodrobnostiInput.value = prefill.podrobnosti || '';

    const gerks = prefill.delovni_nalogi_gerki || [];
    if (gerks.length) {
      gerks.forEach(g => addGerkRow(woGerksListEl, g.gerk_code, g.kolicina_ha ?? '', g.lokacija ?? ''));
    } else {
      addGerkRow(woGerksListEl);
    }
  } else {
    woStevilkaLabel.textContent = 'Številka bo dodeljena samodejno ob shranjevanju';
    addGerkRow(woGerksListEl);
  }

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

  const isEdit   = !!woEditIdInput.value;
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

  let workOrderId;
  let saveError;

  if (isEdit) {
    const { error } = await supabase.from('delovni_nalogi').update(payload).eq('id', woEditIdInput.value);
    saveError = error;
    workOrderId = woEditIdInput.value;
  } else {
    const { data, error } = await supabase.from('delovni_nalogi').insert(payload).select('id').single();
    saveError = error;
    workOrderId = data?.id;
  }

  if (saveError) {
    setWoSaveLoading(false);
    showWoFormError('Napaka pri shranjevanju. Preverite podatke in poskusite znova.');
    return;
  }

  if (isEdit) {
    await supabase.from('delovni_nalogi_gerki').delete().eq('delovni_nalog_id', workOrderId);
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

  showWoFormSuccess(isEdit ? '✓ Nalog posodobljen!' : '✓ Nalog shranjen!');
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
