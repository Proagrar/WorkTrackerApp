import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── State ──────────────────────────────────────────────────────
let currentUser = null;
let logs        = [];
let pendingDeleteId = null;
let fields      = [];
let viewMode    = 'compact';

// ── DOM refs ───────────────────────────────────────────────────
const operatorNameEl = document.getElementById('operatorName');
const greetingEl     = document.getElementById('greeting');
const todayDateEl    = document.getElementById('todayDate');
const logoutBtn      = document.getElementById('logoutBtn');
const addBtn         = document.getElementById('addBtn');
const logsList       = document.getElementById('logsList');
const viewCardsBtn   = document.getElementById('viewCardsBtn');
const viewListBtn    = document.getElementById('viewListBtn');

const statTotal = document.getElementById('statTotal');
const statToday = document.getElementById('statToday');
const statGerk  = document.getElementById('statGerk');

const formModal    = document.getElementById('formModal');
const modalTitle   = document.getElementById('modalTitle');
const modalClose   = document.getElementById('modalClose');
const workLogForm  = document.getElementById('workLogForm');
const editIdInput  = document.getElementById('editId');
const workDateInput= document.getElementById('workDate');
const startHourSel = document.getElementById('startHour');
const startMinSel  = document.getElementById('startMin');
const endHourSel   = document.getElementById('endHour');
const endMinSel    = document.getElementById('endMin');
const gerkInput          = document.getElementById('gerkNumber');
const gerkSuggestionsEl  = document.getElementById('gerkSuggestions');
const gerkHintEl         = document.getElementById('gerkHint');
const descInput          = document.getElementById('description');
const locationEl   = document.getElementById('locationStatus');
const formError    = document.getElementById('formError');
const formSuccess  = document.getElementById('formSuccess');
const saveBtn      = document.getElementById('saveBtn');
const cancelBtn    = document.getElementById('cancelBtn');

const deleteModal      = document.getElementById('deleteModal');
const deleteCancelBtn  = document.getElementById('deleteCancelBtn');
const deleteConfirmBtn = document.getElementById('deleteConfirmBtn');

// ── Session guard ──────────────────────────────────────────────
async function initAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    window.location.replace('index.html');
    return false;
  }
  currentUser = session.user;

  supabase.auth.onAuthStateChange((_event, s) => {
    if (!s) window.location.replace('index.html');
  });

  return true;
}

// ── Time selects — split hour / minute ────────────────────────
function buildTimeOptions() {
  for (const sel of [startHourSel, endHourSel]) {
    for (let h = 0; h < 24; h++) {
      const v = String(h).padStart(2, '0');
      sel.appendChild(new Option(v, v));
    }
  }
  for (const sel of [startMinSel, endMinSel]) {
    for (const m of ['00', '15', '30', '45']) {
      sel.appendChild(new Option(m, m));
    }
  }
}

function getTimeValue(hourSel, minSel) {
  if (hourSel.value === '' || minSel.value === '') return '';
  return `${hourSel.value}:${minSel.value}`;
}

// ── Date / time helpers ────────────────────────────────────────
const MONTHS_SL = ['jan','feb','mar','apr','maj','jun','jul','avg','sep','okt','nov','dec'];

function fmtDate(iso) {
  const [y, m, d] = iso.split('-');
  return `${parseInt(d, 10)}. ${MONTHS_SL[parseInt(m, 10) - 1]} ${y}`;
}

function fmtTime(t) { return t.slice(0, 5); }

function minutesBetween(start, end) {
  const [sh, sm] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  return (eh * 60 + em) - (sh * 60 + sm);
}

function fmtDuration(mins) {
  if (mins <= 0) return '0h';
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

function todayISO() { return new Date().toISOString().slice(0, 10); }

function fmtTodayLong() {
  const d = new Date();
  return `${d.getDate()}. ${MONTHS_SL[d.getMonth()]} ${d.getFullYear()}`;
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
  statTotal.textContent = logs.length;

  const today = todayISO();
  const todayMins = logs
    .filter(l => l.work_date === today)
    .reduce((sum, l) => sum + minutesBetween(fmtTime(l.start_time), fmtTime(l.end_time)), 0);
  statToday.textContent = fmtDuration(todayMins);

  statGerk.textContent = new Set(logs.map(l => l.gerk_number)).size;
}

// ── Load logs ──────────────────────────────────────────────────
async function loadLogs() {
  logsList.innerHTML = `
    <div class="state-loading">
      <div class="spinner"></div>
      <p>Nalaganje...</p>
    </div>`;

  const { data, error } = await supabase
    .from('work_logs')
    .select('*')
    .eq('operator_id', currentUser.id)
    .order('work_date', { ascending: false })
    .order('start_time', { ascending: false });

  if (error) {
    logsList.innerHTML = `<div class="state-empty"><p>Napaka pri nalaganju. Poskusite znova.</p></div>`;
    return;
  }

  logs = data ?? [];
  renderLogs();
  updateStats();
}

// ── Render logs ────────────────────────────────────────────────
function renderLogs() {
  syncViewToggle();
  if (logs.length === 0) {
    logsList.className = 'logs-list';
    logsList.innerHTML = `
      <div class="state-empty">
        <p>Ni še vpisov.<br>Dodajte prvega s tipko <strong>+</strong></p>
      </div>`;
    return;
  }
  viewMode === 'compact' ? renderLogsCompact() : renderLogsCards();
}

function renderLogsCards() {
  logsList.className = 'logs-list';
  logsList.innerHTML = logs.map(log => {
    const start = fmtTime(log.start_time);
    const end   = fmtTime(log.end_time);
    const mins  = minutesBetween(start, end);
    const descEl = log.description
      ? `<div class="log-row"><span class="log-desc">${escHtml(log.description)}</span></div>` : '';
    return `
      <div class="log-card" role="listitem">
        <div class="log-card-top">
          <span class="log-date">${fmtDate(log.work_date)}</span>
          <span class="log-duration">${fmtDuration(mins)}</span>
        </div>
        <div class="log-card-body">
          <div class="log-row">
            <span class="log-icon">⏱</span>
            <span class="log-time-text">${start} – ${end}</span>
          </div>
          <div class="log-row">
            <span class="log-gerk-label">GERK</span>
            <span class="log-gerk-badge">${escHtml(log.gerk_number)}</span>
          </div>
          ${descEl}
        </div>
        <div class="log-card-actions">
          <button class="btn-outline" data-action="edit" data-id="${log.id}">Uredi</button>
          <button class="btn-danger-outline" data-action="delete" data-id="${log.id}">Izbriši</button>
        </div>
      </div>`;
  }).join('');
  wireLogButtons();
}

const EDIT_ICON = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true"><path d="M9.5 1.5l3 3-8 8H1.5v-3l8-8z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const DEL_ICON  = `<svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true"><path d="M2 3.5h10M5 3.5V2h4v1.5M3.5 3.5l.5 8h6l.5-8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

function renderLogsCompact() {
  logsList.className = 'logs-list logs-list--compact';
  const header = `
    <div class="lc-header" aria-hidden="true">
      <span>Datum</span>
      <span>Čas</span>
      <span>GERK</span>
      <span>Ur</span>
      <span></span>
    </div>`;
  const rows = logs.map(log => {
    const start = fmtTime(log.start_time);
    const end   = fmtTime(log.end_time);
    const mins  = minutesBetween(start, end);
    const desc  = log.description
      ? `<p class="lc-desc-row">${escHtml(log.description)}</p>` : '';
    return `
      <div class="log-compact" role="listitem">
        <span class="lc-date">${fmtDate(log.work_date)}</span>
        <span class="lc-time">${start}–${end}</span>
        <span class="lc-gerk">${escHtml(log.gerk_number)}</span>
        <span class="lc-dur">${fmtDuration(mins)}</span>
        <div class="lc-actions">
          <button class="lc-btn" data-action="edit" data-id="${log.id}" title="Uredi">${EDIT_ICON}</button>
          <button class="lc-btn lc-btn--danger" data-action="delete" data-id="${log.id}" title="Izbriši">${DEL_ICON}</button>
        </div>
        ${desc}
      </div>`;
  }).join('');
  logsList.innerHTML = header + rows;
  wireLogButtons();
}

function syncViewToggle() {
  viewCardsBtn?.classList.toggle('active', viewMode === 'cards');
  viewListBtn?.classList.toggle('active',  viewMode === 'compact');
}

viewCardsBtn?.addEventListener('click', () => {
  viewMode = 'cards';
  localStorage.setItem('wt-view', viewMode);
  renderLogs();
});

viewListBtn?.addEventListener('click', () => {
  viewMode = 'compact';
  localStorage.setItem('wt-view', viewMode);
  renderLogs();
});

function escHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Load known fields (GERK autocomplete) ─────────────────────
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
    .filter(f => {
      if (seen.has(f.code)) return false;
      seen.add(f.code);
      return true;
    });
}

function filterFields(query) {
  if (!query) return [];
  const q = query.toLowerCase();
  return fields
    .filter(f =>
      f.code.toLowerCase().includes(q) ||
      (f.name && f.name.toLowerCase().includes(q)) ||
      (f.customer && f.customer.toLowerCase().includes(q))
    )
    .slice(0, 8);
}

function renderSuggestions(matches) {
  if (!matches.length) { gerkSuggestionsEl.hidden = true; return; }
  gerkSuggestionsEl.innerHTML = matches.map(f => {
    const metaParts = [f.name, f.customer, f.area ? `${f.area} ha` : null].filter(Boolean);
    return `
    <li class="gerk-suggestion-item" data-code="${escHtml(f.code)}">
      <span class="gerk-suggestion-code">${escHtml(f.code)}</span>
      ${metaParts.length ? `<span class="gerk-suggestion-meta">${escHtml(metaParts.join(' · '))}</span>` : ''}
    </li>`;
  }).join('');
  gerkSuggestionsEl.hidden = false;
}

function selectSuggestion(code) {
  gerkInput.value = code;
  gerkSuggestionsEl.hidden = true;
  showGerkHint(code);
}

function showGerkHint(code) {
  const f = fields.find(f => f.code === code);
  const parts = [f?.name, f?.customer, f?.area ? `${f.area} ha` : null].filter(Boolean);
  if (parts.length) {
    gerkHintEl.textContent = parts.join(' · ');
    gerkHintEl.hidden = false;
  } else {
    gerkHintEl.hidden = true;
  }
}

gerkInput.addEventListener('input', () => {
  gerkHintEl.hidden = true;
  renderSuggestions(filterFields(gerkInput.value.trim()));
});

gerkInput.addEventListener('focus', () => {
  const val = gerkInput.value.trim();
  if (val) renderSuggestions(filterFields(val));
});

gerkInput.addEventListener('blur', () => {
  setTimeout(() => { gerkSuggestionsEl.hidden = true; }, 150);
});

gerkSuggestionsEl.addEventListener('mousedown', (e) => {
  const item = e.target.closest('.gerk-suggestion-item');
  if (item) selectSuggestion(item.dataset.code);
});

// ── Modal helpers ──────────────────────────────────────────────
function openModal(title, prefill = null) {
  modalTitle.textContent = title;
  workLogForm.reset();
  editIdInput.value = '';
  hideFormFeedback();
  locationEl.hidden = true;
  gerkHintEl.hidden = true;
  gerkSuggestionsEl.hidden = true;

  workDateInput.value = todayISO();

  if (prefill) {
    editIdInput.value      = prefill.id;
    workDateInput.value    = prefill.work_date;
    const [sh, sm] = fmtTime(prefill.start_time).split(':');
    startHourSel.value = sh; startMinSel.value = sm;
    const [eh, em] = fmtTime(prefill.end_time).split(':');
    endHourSel.value = eh; endMinSel.value = em;
    gerkInput.value        = prefill.gerk_number;
    descInput.value        = prefill.description ?? '';
    showGerkHint(prefill.gerk_number);
  }

  formModal.hidden = false;
  document.body.style.overflow = 'hidden';
  gerkInput.focus();
}

function closeModal() {
  formModal.hidden = true;
  document.body.style.overflow = '';
  gerkSuggestionsEl.hidden = true;
  gerkHintEl.hidden = true;
}

function hideFormFeedback() {
  formError.hidden   = true;
  formSuccess.hidden = true;
}

function showFormError(msg) {
  formError.textContent   = msg;
  formError.hidden        = false;
  formSuccess.hidden      = true;
}

function showFormSuccess(msg) {
  formSuccess.textContent = msg;
  formSuccess.hidden      = false;
  formError.hidden        = true;
}

function setSaveLoading(on) {
  saveBtn.disabled   = on;
  cancelBtn.disabled = on;
  saveBtn.querySelector('.btn-label').hidden   = on;
  saveBtn.querySelector('.btn-spinner').hidden = !on;
}

// ── Geolocation ────────────────────────────────────────────────
function captureLocation() {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) {
      return resolve({ status: 'location_unavailable', lat: null, lng: null, accuracy: null, ts: null });
    }

    locationEl.textContent = '📍 Pridobivanje lokacije...';
    locationEl.hidden = false;

    navigator.geolocation.getCurrentPosition(
      ({ coords, timestamp }) => resolve({
        status:   'captured',
        lat:      coords.latitude,
        lng:      coords.longitude,
        accuracy: coords.accuracy,
        ts:       new Date(timestamp).toISOString(),
      }),
      () => resolve({ status: 'permission_denied', lat: null, lng: null, accuracy: null, ts: null }),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
  });
}

// ── Save log ───────────────────────────────────────────────────
workLogForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  hideFormFeedback();

  const isEdit     = !!editIdInput.value;
  const workDate   = workDateInput.value;
  const startTime  = getTimeValue(startHourSel, startMinSel);
  const endTime    = getTimeValue(endHourSel, endMinSel);
  const gerkNumber = gerkInput.value.trim();
  const description= descInput.value.trim();

  if (!workDate)    return showFormError('Izberite datum dela.');
  if (!startTime)   return showFormError('Izberite čas začetka.');
  if (!endTime)     return showFormError('Izberite čas konca.');
  if (endTime <= startTime) return showFormError('Čas konca mora biti poznejši od časa začetka.');
  if (!gerkNumber)  return showFormError('Vnesite GERK številko.');
  const knownField = fields.find(f => f.code === gerkNumber);
  if (!knownField && !/^\d{7}$/.test(gerkNumber))
    return showFormError('GERK številka mora vsebovati točno 7 številk.');

  setSaveLoading(true);

  let locationFields = {};
  if (!isEdit) {
    const loc = await captureLocation();
    locationFields = {
      latitude:             loc.lat,
      longitude:            loc.lng,
      location_accuracy:    loc.accuracy,
      location_captured_at: loc.ts,
      location_status:      loc.status,
    };
    locationEl.textContent = loc.status === 'captured'
      ? '📍 Lokacija zajeta'
      : '📍 Lokacija ni bila dostopna';
    locationEl.hidden = false;
  }

  let error;

  if (isEdit) {
    ({ error } = await supabase
      .from('work_logs')
      .update({
        work_date:   workDate,
        start_time:  startTime,
        end_time:    endTime,
        gerk_number: gerkNumber,
        description: description || null,
      })
      .eq('id', editIdInput.value)
      .eq('operator_id', currentUser.id));
  } else {
    ({ error } = await supabase
      .from('work_logs')
      .insert({
        operator_id:  currentUser.id,
        work_date:    workDate,
        start_time:   startTime,
        end_time:     endTime,
        gerk_number:  gerkNumber,
        description:  description || null,
        ...locationFields,
      }));
  }

  setSaveLoading(false);

  if (error) {
    showFormError('Napaka pri shranjevanju. Preverite podatke in poskusite znova.');
    return;
  }

  showFormSuccess(isEdit ? '✓ Vpis posodobljen!' : '✓ Vpis shranjen!');
  await loadLogs();
  setTimeout(closeModal, 1000);
});

// ── Wire log action buttons after every render ────────────────
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

// ── Event wiring ───────────────────────────────────────────────
logoutBtn.addEventListener('click', async () => {
  await supabase.auth.signOut();
  window.location.replace('index.html');
});

addBtn.addEventListener('click', () => openModal('Nov vpis'));
modalClose.addEventListener('click', closeModal);
cancelBtn.addEventListener('click', closeModal);

formModal.addEventListener('click', (e) => {
  if (e.target === formModal) closeModal();
});
deleteModal.addEventListener('click', (e) => {
  if (e.target === deleteModal) closeDeleteModal();
});

// Close modal on Escape key
document.addEventListener('keydown', (e) => {
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
  loadFields(); // non-blocking — suggestions appear once loaded

  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name')
    .eq('id', currentUser.id)
    .maybeSingle();

  const displayName = profile?.full_name ?? currentUser.email;
  operatorNameEl.textContent = displayName;
  renderGreeting(displayName);

  await loadLogs();
}

boot();
