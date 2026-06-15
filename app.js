import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── State ──────────────────────────────────────────────────────
let currentUser  = null;
let currentRole  = 'operator';
let profileMap   = {};
let logs         = [];
let fields       = [];
let pendingDeleteId = null;
let viewMode     = 'compact';
let currentMonth = new Date().toISOString().slice(0, 7);

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
const editIdInput = document.getElementById('editId');
const workDateInput = document.getElementById('workDate');
const workHourSel = document.getElementById('workHour');
const workMinSel  = document.getElementById('workMin');
const roadHourSel = document.getElementById('roadHour');
const roadMinSel  = document.getElementById('roadMin');
const gerksListEl = document.getElementById('gerksList');
const addGerkBtn  = document.getElementById('addGerkBtn');
const tractorInput = document.getElementById('tractor');
const descInput   = document.getElementById('description');
const formError   = document.getElementById('formError');
const formSuccess = document.getElementById('formSuccess');
const saveBtn     = document.getElementById('saveBtn');
const cancelBtn   = document.getElementById('cancelBtn');

const deleteModal      = document.getElementById('deleteModal');
const deleteCancelBtn  = document.getElementById('deleteCancelBtn');
const deleteConfirmBtn = document.getElementById('deleteConfirmBtn');

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
  for (const sel of [workHourSel, roadHourSel]) {
    for (let h = 0; h <= 23; h++) sel.appendChild(new Option(String(h), String(h)));
  }
  for (const sel of [workMinSel, roadMinSel]) {
    for (const m of ['00', '15', '30', '45']) sel.appendChild(new Option(m, m));
  }
  workHourSel.value = '0'; workMinSel.value = '00';
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

function isEditable(log) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 7);
  cutoff.setHours(0, 0, 0, 0);
  return new Date(log.work_date) >= cutoff;
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

  if (currentRole !== 'admin') {
    query = query.eq('operator_id', currentUser.id);
  } else {
    const { data: profs } = await supabase.from('profiles').select('id, full_name');
    profileMap = Object.fromEntries((profs ?? []).map(p => [p.id, p.full_name]));
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
    const operatorRow = currentRole === 'admin'
      ? `<div class="log-row"><span class="log-operator-badge">${escHtml(profileMap[log.operator_id] ?? '—')}</span></div>` : '';
    const editable = isEditable(log);
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
          <button class="btn-outline" data-action="edit" data-id="${log.id}"
            ${editable ? '' : 'disabled title="Starejše od 7 dni"'}>Uredi</button>
          <button class="btn-danger-outline" data-action="delete" data-id="${log.id}">Izbriši</button>
        </div>
      </div>`;
  }).join('');
  wireLogButtons();
}

const EDIT_ICON = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true"><path d="M9.5 1.5l3 3-8 8H1.5v-3l8-8z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const DEL_ICON  = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true"><path d="M2 3.5h10M5 3.5V2h4v1.5M3.5 3.5l.5 8h6l.5-8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

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
    const editable = isEditable(log);

    const extras = [
      currentRole === 'admin' ? escHtml(profileMap[log.operator_id] ?? '—') : null,
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
          <button class="lc-btn${editable ? '' : ' lc-btn--locked'}"
            data-action="edit" data-id="${log.id}"
            title="${editable ? 'Uredi' : 'Starejše od 7 dni'}"
            ${editable ? '' : 'disabled'}>${EDIT_ICON}</button>
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

function addGerkRow(code = '', hectares = '') {
  const row = document.createElement('div');
  row.className = 'gerk-row';
  row.innerHTML = `
    <div class="gerk-wrap">
      <input type="text" class="field-input gerk-code-input"
             placeholder="GERK številka ali ime" autocomplete="off">
      <ul class="gerk-suggestions" hidden></ul>
      <p class="field-hint gerk-hint" hidden></p>
    </div>
    <input type="number" class="field-input gerk-ha-input"
           placeholder="ha" step="0.0001" min="0" max="9999">
    <button type="button" class="gerk-remove-btn" aria-label="Odstrani">✕</button>`;

  const codeInput     = row.querySelector('.gerk-code-input');
  const haInput       = row.querySelector('.gerk-ha-input');
  const suggestionsEl = row.querySelector('.gerk-suggestions');
  const hintEl        = row.querySelector('.gerk-hint');
  const removeBtn     = row.querySelector('.gerk-remove-btn');

  codeInput.value = code;
  if (hectares !== '' && hectares != null) haInput.value = hectares;

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
    if (!gerksListEl.querySelector('.gerk-row')) addGerkRow();
  });

  gerksListEl.appendChild(row);
  return codeInput;
}

function getFormGerks() {
  return Array.from(gerksListEl.querySelectorAll('.gerk-row')).map(row => ({
    code:     row.querySelector('.gerk-code-input').value.trim(),
    hectares: row.querySelector('.gerk-ha-input').value
              ? parseFloat(row.querySelector('.gerk-ha-input').value) : null,
  })).filter(g => g.code);
}

addGerkBtn.addEventListener('click', () => {
  const input = addGerkRow();
  input.focus();
});

// ── Modal ──────────────────────────────────────────────────────
function openModal(title, prefill = null) {
  modalTitle.textContent = title;
  workLogForm.reset();
  editIdInput.value = '';
  hideFormFeedback();
  workDateInput.value = todayISO();
  workHourSel.value = '0'; workMinSel.value = '00';
  roadHourSel.value = '0'; roadMinSel.value = '00';
  gerksListEl.innerHTML = '';
  updateTractorDatalist();

  if (prefill) {
    editIdInput.value = prefill.id;
    workDateInput.value = prefill.work_date;
    setDurationSels(workHourSel, workMinSel, prefill.work_duration);
    setDurationSels(roadHourSel, roadMinSel, prefill.road_duration);
    tractorInput.value = prefill.tractor || '';
    descInput.value    = prefill.description || '';
    const gerks = prefill.work_log_gerks || [];
    if (gerks.length) {
      gerks.forEach(g => addGerkRow(g.gerk_code, g.hectares ?? ''));
    } else {
      addGerkRow();
    }
  } else {
    addGerkRow();
  }

  formModal.hidden = false;
  document.body.style.overflow = 'hidden';
}

function closeModal() {
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

function setSaveLoading(on) {
  saveBtn.disabled   = on;
  cancelBtn.disabled = on;
  saveBtn.querySelector('.btn-label').hidden   = on;
  saveBtn.querySelector('.btn-spinner').hidden = !on;
}

// ── Save ───────────────────────────────────────────────────────
workLogForm.addEventListener('submit', async e => {
  e.preventDefault();
  hideFormFeedback();

  const isEdit       = !!editIdInput.value;
  const workDate     = workDateInput.value;
  const workDuration = getDurationMins(workHourSel, workMinSel);
  const roadDuration = getDurationMins(roadHourSel, roadMinSel);
  const gerkRows     = getFormGerks();

  if (!workDate)         return showFormError('Izberite datum dela.');
  if (workDuration <= 0) return showFormError('Vnesite čas dela na traktorju.');
  if (!gerkRows.length)  return showFormError('Dodajte vsaj en GERK.');

  for (const g of gerkRows) {
    const known = fields.find(f => f.code === g.code);
    if (!known && !/^\d{7}$/.test(g.code))
      return showFormError(`Neveljaven GERK: "${g.code}" (mora biti 7-mestna številka).`);
  }

  setSaveLoading(true);

  const logPayload = {
    work_date:     workDate,
    work_duration: workDuration,
    road_duration: roadDuration || null,
    tractor:       tractorInput.value.trim() || null,
    description:   descInput.value.trim()    || null,
  };

  let workLogId;
  let saveError;

  if (isEdit) {
    const { error } = await supabase
      .from('work_logs')
      .update(logPayload)
      .eq('id', editIdInput.value)
      .eq('operator_id', currentUser.id);
    saveError = error;
    workLogId = editIdInput.value;
  } else {
    const { data, error } = await supabase
      .from('work_logs')
      .insert({ ...logPayload, operator_id: currentUser.id })
      .select('id')
      .single();
    saveError = error;
    workLogId = data?.id;
  }

  if (saveError) {
    setSaveLoading(false);
    showFormError('Napaka pri shranjevanju. Preverite podatke in poskusite znova.');
    return;
  }

  if (isEdit) {
    await supabase.from('work_log_gerks').delete().eq('work_log_id', workLogId);
  }

  const { error: gerkError } = await supabase
    .from('work_log_gerks')
    .insert(gerkRows.map(g => ({ work_log_id: workLogId, gerk_code: g.code, hectares: g.hectares })));

  setSaveLoading(false);

  if (gerkError) {
    showFormError('Napaka pri shranjevanju GERKOV.');
    return;
  }

  saveTractorToHistory(tractorInput.value.trim());
  showFormSuccess(isEdit ? '✓ Vpis posodobljen!' : '✓ Vpis shranjen!');
  await loadLogs();
  setTimeout(closeModal, 1000);
});

// ── Wire buttons ───────────────────────────────────────────────
function wireLogButtons() {
  logsList.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => {
      const log = logs.find(l => l.id === btn.dataset.id);
      if (log) openModal('Uredi vpis', log);
    });
  });
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

addBtn.addEventListener('click', () => openModal('Nov vpis'));
modalClose.addEventListener('click', closeModal);
cancelBtn.addEventListener('click', closeModal);

formModal.addEventListener('click', e => { if (e.target === formModal) closeModal(); });
deleteModal.addEventListener('click', e => { if (e.target === deleteModal) closeDeleteModal(); });

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (!formModal.hidden)   closeModal();
    if (!deleteModal.hidden) closeDeleteModal();
  }
});

// ── Boot ───────────────────────────────────────────────────────
async function boot() {
  const authed = await initAuth();
  if (!authed) return;

  buildTimeOptions();
  renderMonthLabel();
  loadFields();

  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name, role')
    .eq('id', currentUser.id)
    .maybeSingle();

  const displayName = profile?.full_name ?? currentUser.email;
  currentRole = profile?.role ?? 'operator';
  operatorNameEl.textContent = displayName;
  adminBadge.hidden = currentRole !== 'admin';
  renderGreeting(displayName);

  await loadLogs();
}

boot();
