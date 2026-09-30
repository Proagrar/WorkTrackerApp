import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

// Own client instance, deliberately — this module is self-contained (own
// state, own DOM refs, own event wiring) and app.js is already huge; sharing
// its client would just add cross-module coupling for no real benefit (both
// instances read the same session from the same storage).
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const MONTHS = ['januar', 'februar', 'marec', 'april', 'maj', 'junij', 'julij', 'avgust', 'september', 'oktober', 'november', 'december'];
const WEEKDAYS = ['Pon', 'Tor', 'Sre', 'Čet', 'Pet', 'Sob', 'Ned'];
const MODAL_CLOSE_MS = 300; // matches app.js's own modal fade timing
// Deterministic per-operator color for the calendar dot — hashed from the
// operator id so it's stable across reloads without needing to store a map.
const OPERATOR_PALETTE = ['#E63946', '#2A9D8F', '#E9C46A', '#457B9D', '#F4A261', '#9B5DE5', '#00B4D8', '#FF6B6B', '#6A994E', '#C77DFF'];
function operatorColor(key) {
  if (key === 'none') return '#9AA3B2';
  let hash = 0;
  for (let i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) >>> 0;
  return OPERATOR_PALETTE[hash % OPERATOR_PALETTE.length];
}

let orders = [];
let planningLoaded = false;
let planEntries = [];
// The full "eligible izvajalec" roster (same list Izvajalci/order-creation
// use), not just operators who happen to have an open order right now —
// so the filter still lets you pick someone with zero current orders.
let eligibleOperators = [];
let selectedOrderId = null;
let selectedPlanId = null;
let selectedOperators = new Set();
let calendarDate = new Date();
let map = null;

const els = {
  tab: document.getElementById('tabPlaniranje'),
  cards: document.getElementById('workOrderCards'),
  count: document.getElementById('planningCount'),
  hint: document.getElementById('planningHint'),
  title: document.getElementById('calendarTitle'),
  grid: document.getElementById('calendarGrid'),
  prev: document.getElementById('calendarPrev'),
  next: document.getElementById('calendarNext'),
  today: document.getElementById('calendarToday'),
  from: document.getElementById('calendarFrom'),
  to: document.getElementById('calendarTo'),
  operatorFilterButton: document.getElementById('operatorFilterButton'),
  operatorFilterMenu: document.getElementById('operatorFilterMenu'),
  modal: document.getElementById('planGerkModal'),
  modalTitle: document.getElementById('workOrderModalTitle'),
  modalClose: document.getElementById('workOrderModalClose'),
  list: document.getElementById('gerkSelectionList'),
  summary: document.getElementById('gerkSelectionSummary'),
  selectAll: document.getElementById('selectAllGerks'),
  save: document.getElementById('saveGerkSelection'),
  map: document.getElementById('gerkMap'),
  mapHint: document.getElementById('mapHint'),
};

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function localDate(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseDate(value) {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
}

function addDays(date, amount) {
  const result = new Date(date);
  result.setDate(result.getDate() + amount);
  return result;
}

function firstCalendarDay(date) {
  const first = new Date(date.getFullYear(), date.getMonth(), 1);
  const weekday = (first.getDay() + 6) % 7;
  return addDays(first, -weekday);
}

function formatArea(area) {
  const number = Number(area);
  if (!Number.isFinite(number)) return '—';
  return `${new Intl.NumberFormat('sl-SI', { maximumFractionDigits: 2 }).format(number)} ha`;
}

function showModal(el) {
  el.hidden = false;
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('modal-backdrop--visible')));
}
function hideModal(el) {
  el.classList.remove('modal-backdrop--visible');
  setTimeout(() => { el.hidden = true; }, MODAL_CLOSE_MS);
}

// The plannable unit is a delovni_nalogi_gerki *line* (its own id), not a
// fields row — a compound "A+B+C" GERK code is one line/one checkbox, same
// as everywhere else in the app (get_work_order_gerk_shapes etc.).
function normalizeGerkLine(link, lastnostById, dictByKey) {
  const field = link.fields || null;
  const lastnost = field?.gerk_lastnost_id != null ? lastnostById.get(field.gerk_lastnost_id) : null;
  const rabaId = lastnost?.lastnost?.RABA_ID ?? null;
  const country = String(lastnost?.drzava || '').toUpperCase();
  const type = rabaId != null ? (dictByKey.get(`${country}:${rabaId}`) ?? 'Ni podatka') : 'Ni podatka';
  return {
    id: link.id,
    code: link.gerk_code,
    area: field?.area_ha ?? null,
    type,
  };
}

function normalizeOrder(row, lastnostById, dictByKey, operatorNames, segmentCountById) {
  const izvajalecId = row.izvajalec || null;
  const izvajalecKey = izvajalecId || 'none';
  const izvajalecName = izvajalecId ? (operatorNames.get(izvajalecId) ?? 'Neznan izvajalec') : 'Ni izvajalca';
  return {
    id: row.id,
    stevilka: row.stevilka || '—',
    customerName: row.customers?.naziv || row.customers?.company_name || 'Brez stranke',
    izvajalecKey,
    izvajalecName,
    segmentCount: segmentCountById.get(row.id) ?? 0,
    gerkLines: (row.delovni_nalogi_gerki ?? []).map(link => normalizeGerkLine(link, lastnostById, dictByKey)),
  };
}

function getOrder(id) { return orders.find(order => String(order.id) === String(id)); }

function matchesOperator(order) {
  return !selectedOperators.size || selectedOperators.has(order.izvajalecKey);
}

function renderOperatorFilter() {
  // Same roster as everywhere else in the app (profiles.eligible_izvajalec),
  // not just whoever happens to have an open order right now — plus "Ni
  // izvajalca" for unassigned orders, which are a normal, common case.
  const entries = [
    ['none', 'Ni izvajalca'],
    ...eligibleOperators
      .map(op => [op.id, op.name])
      .sort((left, right) => left[1].localeCompare(right[1], 'sl')),
  ];
  const validKeys = new Set(entries.map(([key]) => key));
  selectedOperators = new Set([...selectedOperators].filter(key => validKeys.has(key)));
  els.operatorFilterMenu.innerHTML = entries.map(([key, name]) => `<label class="operator-filter-option">
    <input type="checkbox" value="${esc(key)}" ${selectedOperators.has(key) ? 'checked' : ''} />
    <span>${esc(name)}</span>
  </label>`).join('');
  els.operatorFilterButton.textContent = selectedOperators.size ? `${selectedOperators.size} izbranih` : 'Vsi izvajalci';
}

async function loadPlanningData() {
  if (planningLoaded) return;
  planningLoaded = true;
  els.hint.textContent = 'Nalaganje delovnih nalogov ...';

  // Same scope as the main Delovni Nalogi list's default view: every
  // non-archived order, any status (that list has no server-side status
  // filter either — see loadWorkOrders()/filteredWorkOrders() in app.js).
  // Orders with nothing left to schedule simply won't produce a card, via
  // the unplannedGerkLines() check in renderCards() below.
  const [ordersRes, profilesRes, segmentCountsRes] = await Promise.all([
    supabase
      .from('delovni_nalogi')
      .select('id, stevilka, izvajalec, customers(naziv, company_name), delovni_nalogi_gerki(id, gerk_code, field_id, fields(id, area_ha, gerk_lastnost_id))')
      .is('deleted_at', null),
    supabase.from('profiles').select('id, full_name, eligible_izvajalec'),
    supabase.rpc('get_work_orders_segment_counts'),
  ]);

  if (ordersRes.error) {
    els.hint.textContent = 'Delovnih nalogov ni mogoče prebrati.';
    els.cards.innerHTML = `<div class="planning-error">${esc(ordersRes.error.message)}</div>`;
    return;
  }

  const rows = ordersRes.data ?? [];
  const profiles = profilesRes.data ?? [];
  const operatorNames = new Map(profiles.map(p => [p.id, p.full_name || 'Brez imena']));
  eligibleOperators = profiles
    .filter(p => p.eligible_izvajalec)
    .map(p => ({ id: p.id, name: p.full_name || 'Brez imena' }));
  renderOperatorFilter();

  const segmentCountById = new Map((segmentCountsRes.data ?? []).map(r => [r.delovni_nalog_id, Number(r.segment_count)]));

  const lastnostIds = [...new Set(rows.flatMap(row =>
    (row.delovni_nalogi_gerki ?? [])
      .map(link => link.fields?.gerk_lastnost_id)
      .filter(id => id != null)
  ))];

  const { data: lastnosti, error: lastnostError } = lastnostIds.length
    ? await supabase.from('gerk_lastnost').select('gerk_id, drzava, lastnost').in('gerk_id', lastnostIds)
    : { data: [], error: null };
  if (lastnostError) els.hint.textContent = `Tabele gerk_lastnost ni mogoče prebrati: ${lastnostError.message}`;
  const lastnostById = new Map((lastnosti ?? []).map(l => [l.gerk_id, l]));

  const { data: dictionary, error: dictionaryError } = await supabase
    .from('gerk_raba_id_slovar')
    .select('country, raba_id, slovenski_naziv');
  if (dictionaryError) els.hint.textContent = `Šifranta gerk_raba_id_slovar ni mogoče prebrati: ${dictionaryError.message}`;
  const dictByKey = new Map((dictionary ?? []).map(d => [`${String(d.country ?? '').toUpperCase()}:${d.raba_id}`, d.slovenski_naziv]));

  orders = rows.map(row => normalizeOrder(row, lastnostById, dictByKey, operatorNames, segmentCountById));

  const { data: plans, error: planError } = await supabase
    .from('delovni_nalogi_planiranje')
    .select('id, delovni_nalog_id, plan_date, delovni_nalogi_planiranje_gerki(delovni_nalog_gerk_id)');

  planEntries = planError ? [] : (plans ?? []).map(plan => ({
    id: plan.id,
    orderId: plan.delovni_nalog_id,
    date: plan.plan_date,
    gerkLineIds: new Set((plan.delovni_nalogi_planiranje_gerki ?? []).map(item => item.delovni_nalog_gerk_id)),
  }));

  els.hint.textContent = orders.length ? 'Povlecite nalog na dan v koledarju.' : 'Ni odprtih delovnih nalogov.';
  renderAll();
}

function entriesForOrder(order) { return planEntries.filter(entry => String(entry.orderId) === String(order.id)); }
function plannedGerkLineIds(order) {
  return new Set(entriesForOrder(order).flatMap(entry => [...entry.gerkLineIds]));
}
function unplannedGerkLines(order) {
  const planned = plannedGerkLineIds(order);
  return order.gerkLines.filter(line => !planned.has(line.id));
}
function gerkLinesForEntry(order, entry) {
  const selected = entry?.gerkLineIds ?? new Set();
  return order.gerkLines.filter(line => selected.has(line.id));
}
function groupedAreasForLines(lines) {
  const groups = new Map();
  for (const line of lines) {
    const current = groups.get(line.type) ?? 0;
    groups.set(line.type, current + (Number(line.area) || 0));
  }
  return [...groups.entries()];
}

function groupedAreas(order) {
  return groupedAreasForLines(unplannedGerkLines(order));
}

function operatorOptionsHtml(selectedKey) {
  const options = [['none', 'Ni izvajalca'], ...eligibleOperators.map(op => [op.id, op.name])];
  return options.map(([key, name]) =>
    `<option value="${esc(key)}" ${key === selectedKey ? 'selected' : ''}>${esc(name)}</option>`
  ).join('');
}

function renderCards() {
  const available = orders
    .filter(order => matchesOperator(order) && unplannedGerkLines(order).length > 0)
    .sort((left, right) => (Number(right.stevilka) || 0) - (Number(left.stevilka) || 0));
  els.count.textContent = String(available.length);
  els.cards.innerHTML = available.map(order => {
    const lines = unplannedGerkLines(order);
    const totalHa = lines.reduce((sum, line) => sum + (Number(line.area) || 0), 0);
    const areas = groupedAreasForLines(lines).map(([type, area]) => `<span class="area-chip"><b>${esc(type)}</b> ${formatArea(area)}</span>`).join('');
    return `<article class="work-order-card" draggable="true" data-order-id="${esc(order.id)}" role="listitem" tabindex="0">
      <div class="work-order-card-head">
        <h3>${esc(order.stevilka)} – ${esc(order.customerName)}</h3>
        <span class="order-gerk-count">${lines.length} GERK · ${order.segmentCount} segm.</span>
      </div>
      <select class="card-operator-select" draggable="false" data-order-id="${esc(order.id)}">${operatorOptionsHtml(order.izvajalecKey)}</select>
      <div class="area-chips">
        <span class="area-chip area-chip--total"><b>Skupaj</b> ${formatArea(totalHa)}</span>
        ${areas}
      </div>
    </article>`;
  }).join('');

  els.cards.querySelectorAll('.work-order-card').forEach(card => {
    card.addEventListener('dragstart', event => event.dataTransfer.setData('text/plain', `order:${card.dataset.orderId}`));
    card.addEventListener('dblclick', () => openOrderModal(card.dataset.orderId));
    card.addEventListener('keydown', event => {
      if (event.target !== card) return; // let the operator <select> handle its own keys
      if (event.key === 'Enter' || event.key === ' ') openOrderModal(card.dataset.orderId);
    });
  });
  els.cards.querySelectorAll('.card-operator-select').forEach(select => {
    // Stop the card's own drag/dblclick from hijacking normal <select> use.
    select.addEventListener('mousedown', event => event.stopPropagation());
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', () => reassignOperator(select.dataset.orderId, select.value));
  });
}

async function reassignOperator(orderId, izvajalecKey) {
  const order = getOrder(orderId);
  if (!order) return;
  const izvajalecId = izvajalecKey === 'none' ? null : izvajalecKey;
  const { error } = await supabase.from('delovni_nalogi').update({ izvajalec: izvajalecId }).eq('id', orderId);
  if (error) {
    els.hint.textContent = `Sprememba izvajalca ni uspela: ${error.message}`;
    return;
  }
  order.izvajalecKey = izvajalecKey;
  order.izvajalecName = izvajalecId
    ? (eligibleOperators.find(op => op.id === izvajalecId)?.name ?? 'Neznan izvajalec')
    : 'Ni izvajalca';
  renderOperatorFilter();
  renderAll();
}

function renderCalendar() {
  const fromDate = els.from.value || null;
  const toDate = els.to.value || null;
  const displayStart = fromDate ? parseDate(fromDate) : firstCalendarDay(calendarDate);
  const year = displayStart.getFullYear();
  const month = displayStart.getMonth();
  els.title.textContent = `${MONTHS[month]} ${year}`;
  const leadingDays = fromDate ? (displayStart.getDay() + 6) % 7 : 0;
  const today = localDate();
  let html = WEEKDAYS.map(day => `<div class="calendar-weekday">${day}</div>`).join('');
  html += Array.from({ length: leadingDays }, () => '<div class="calendar-day calendar-day--blank" aria-hidden="true"></div>').join('');

  for (let index = 0; index < 42 - leadingDays; index++) {
    const date = addDays(displayStart, index);
    const iso = localDate(date);
    const inRange = (!fromDate || iso >= fromDate) && (!toDate || iso <= toDate);
    const dayEntries = planEntries.filter(entry => {
      const order = getOrder(entry.orderId);
      return entry.date === iso && entry.gerkLineIds.size > 0 && order && matchesOperator(order);
    });
    const dayAreas = groupedAreasForLines(dayEntries.flatMap(entry => {
      const order = getOrder(entry.orderId);
      return order ? gerkLinesForEntry(order, entry) : [];
    }))
      .map(([type, area]) => `<span class="calendar-day-area">${esc(type)} ${formatArea(area)}</span>`)
      .join('');
    const classes = ['calendar-day'];
    if (date.getMonth() !== month) classes.push('is-outside');
    if (iso === today) classes.push('is-today');
    if (!inRange) classes.push('is-out-of-range');
    html += `<div class="${classes.join(' ')}" data-date="${iso}" role="gridcell">
      <span class="calendar-day-number">${date.getDate()}</span>
      <div class="calendar-day-areas">${dayAreas}</div>
      <div class="calendar-day-orders">${dayEntries.map(renderCalendarOrder).join('')}</div>
    </div>`;
  }
  els.grid.innerHTML = html;
  els.grid.querySelectorAll('.calendar-day').forEach(day => {
    day.addEventListener('dragover', event => { event.preventDefault(); day.classList.add('is-drop-target'); });
    day.addEventListener('dragleave', () => day.classList.remove('is-drop-target'));
    day.addEventListener('drop', event => {
      event.preventDefault();
      day.classList.remove('is-drop-target');
      const transfer = event.dataTransfer.getData('text/plain');
      if (transfer.startsWith('plan:')) movePlan(transfer.slice(5), day.dataset.date);
      if (transfer.startsWith('order:')) placeOrder(transfer.slice(6), day.dataset.date);
    });
  });
  els.grid.querySelectorAll('.calendar-order').forEach(card => {
    card.addEventListener('click', () => selectCalendarOrder(card));
    card.addEventListener('dblclick', () => openOrderModal(card.dataset.orderId, card.dataset.planId));
    card.addEventListener('contextmenu', event => {
      event.preventDefault();
      removeOrderFromCalendar(card.dataset.planId);
    });
    card.addEventListener('dragstart', event => event.dataTransfer.setData('text/plain', `plan:${card.dataset.planId}`));
  });
}

function renderCalendarOrder(entry) {
  const sourceOrder = getOrder(entry.orderId);
  const complete = sourceOrder ? gerkLinesForEntry(sourceOrder, entry).length === sourceOrder.gerkLines.length : false;
  // Green/yellow (is-complete/is-partial) still shows scheduling progress;
  // the dot's color is per-operator, so you can tell whose work is whose
  // at a glance without opening anything.
  const color = operatorColor(sourceOrder?.izvajalecKey ?? 'none');
  const stevilka = sourceOrder ? `${esc(sourceOrder.stevilka)} – ` : '';
  return `<button class="calendar-order ${complete ? 'is-complete' : 'is-partial'}" draggable="true" data-order-id="${esc(entry.orderId)}" data-plan-id="${esc(entry.id)}" type="button" title="${esc(sourceOrder?.izvajalecName ?? '')}">
    <span class="calendar-order-name"><span class="calendar-order-dot" style="background:${color}"></span>${stevilka}${esc(sourceOrder?.customerName ?? 'Delovni nalog')}</span>
  </button>`;
}

function selectCalendarOrder(card) {
  els.grid.querySelectorAll('.calendar-order.is-selected').forEach(item => item.classList.remove('is-selected'));
  card.classList.add('is-selected');
  selectedOrderId = card.dataset.orderId;
  selectedPlanId = card.dataset.planId;
}

async function placeOrder(orderId, date) {
  const order = getOrder(orderId);
  if (!order) return;
  const selectedIds = unplannedGerkLines(order).map(line => line.id);
  if (!selectedIds.length) return;
  await savePlan({ orderId: order.id, date, gerkLineIds: new Set(selectedIds) });
  renderAll();
}

async function movePlan(planId, date) {
  const entry = planEntries.find(item => String(item.id) === String(planId));
  if (!entry || entry.date === date) return;
  const { error } = await supabase
    .from('delovni_nalogi_planiranje')
    .update({ plan_date: date })
    .eq('id', entry.id);
  if (error) {
    els.hint.textContent = `Premik ni uspel: ${error.message}`;
    return;
  }
  entry.date = date;
  renderAll();
}

async function savePlan(entry) {
  const { data: plan, error } = await supabase
    .from('delovni_nalogi_planiranje')
    .insert({ delovni_nalog_id: entry.orderId, plan_date: entry.date })
    .select('id')
    .single();
  if (error) {
    els.hint.textContent = `Shranjevanje ni uspelo: ${error.message}`;
    return false;
  }
  const selected = [...entry.gerkLineIds].map(id => ({ plan_id: plan.id, delovni_nalog_gerk_id: id }));
  if (selected.length) await supabase.from('delovni_nalogi_planiranje_gerki').insert(selected);
  planEntries.push({ id: plan.id, orderId: entry.orderId, date: entry.date, gerkLineIds: new Set(entry.gerkLineIds) });
  return true;
}

async function removeOrderFromCalendar(planId) {
  const entry = planEntries.find(item => String(item.id) === String(planId));
  if (!entry) return;
  const { error } = await supabase.from('delovni_nalogi_planiranje').delete().eq('id', entry.id);
  if (error) {
    els.hint.textContent = `Brisanje ni uspelo: ${error.message}`;
    return;
  }
  planEntries = planEntries.filter(item => String(item.id) !== String(planId));
  renderAll();
}

function openOrderModal(orderId, planId = null) {
  const order = getOrder(orderId);
  if (!order) return;
  selectedOrderId = order.id;
  selectedPlanId = planId;
  const entry = planEntries.find(item => String(item.id) === String(planId));
  const selectedIds = entry?.gerkLineIds ?? new Set();
  els.modalTitle.textContent = order.customerName;
  const sortedLines = [...order.gerkLines].sort((left, right) => Number(selectedIds.has(left.id)) - Number(selectedIds.has(right.id)));
  els.list.innerHTML = sortedLines.map(line => {
    const selected = selectedIds.has(line.id);
    return `<label class="gerk-selection-row ${selected ? 'is-planned' : ''}">
    <input type="checkbox" data-gerk-line-id="${esc(line.id)}" ${selected ? 'checked' : ''} />
    <span class="gerk-selection-code">${esc(line.code)}</span>
    <span class="gerk-selection-meta">${esc(line.type)} · ${formatArea(line.area)}</span>
  </label>`;
  }).join('');
  showModal(els.modal);
  document.body.style.overflow = 'hidden';
  syncSelectionSummary();
  renderMap(order);
}

function closeOrderModal() {
  hideModal(els.modal);
  document.body.style.overflow = '';
  if (map) { map.remove(); map = null; }
}

function syncSelectionSummary() {
  const order = getOrder(selectedOrderId);
  if (!order) return;
  const checked = [...els.list.querySelectorAll('input:checked')].length;
  els.summary.textContent = `${checked} od ${order.gerkLines.length} GERK-ov izbranih`;
  els.selectAll.checked = checked > 0 && checked === order.gerkLines.length;
  els.selectAll.indeterminate = checked > 0 && checked < order.gerkLines.length;
}

async function saveSelection() {
  const order = getOrder(selectedOrderId);
  if (!order) return;
  const selectedIds = new Set([...els.list.querySelectorAll('input:checked')].map(input => input.dataset.gerkLineId));
  if (selectedPlanId) {
    const entry = planEntries.find(item => String(item.id) === String(selectedPlanId));
    if (entry) {
      if (selectedIds.size === 0) {
        await removeOrderFromCalendar(entry.id);
      } else {
        const { error } = await supabase
          .from('delovni_nalogi_planiranje_gerki')
          .delete()
          .eq('plan_id', entry.id);
        if (!error) {
          const selected = [...selectedIds].map(id => ({ plan_id: entry.id, delovni_nalog_gerk_id: id }));
          const insertResult = await supabase.from('delovni_nalogi_planiranje_gerki').insert(selected);
          if (!insertResult.error) entry.gerkLineIds = selectedIds;
        }
        renderAll();
      }
    }
  } else if (selectedIds.size) {
    // Opened straight from a card (dblclick), not an existing calendar entry
    // — this saves it as a new plan on today's date.
    await savePlan({ orderId: order.id, date: localDate(), gerkLineIds: selectedIds });
    renderAll();
  }
  closeOrderModal();
}

// Renders both registry-resolved shapes (get_work_order_gerk_shapes) and
// segmentation-zone shapes (get_work_order_gerk_segments) — same pair
// showWoDetailMap() in app.js calls, so this stays compound-GERK-code-aware
// and visually consistent with the rest of the app's maps, instead of the
// older gerk_lastnost/gerk_polygon join this branch originally used.
async function renderMap(order) {
  els.mapHint.textContent = '';
  if (!window.L) {
    els.mapHint.textContent = 'Zemljevid ni na voljo, ker knjižnice Leaflet ni mogoče naložiti.';
    return;
  }
  map = window.L.map(els.map, { zoomControl: true }).setView([46.15, 14.995], 8);
  window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '&copy; OpenStreetMap' }).addTo(map);
  const bounds = [];

  const [shapesRes, segmentsRes] = await Promise.all([
    supabase.rpc('get_work_order_gerk_shapes', { p_work_order_id: order.id }),
    supabase.rpc('get_work_order_gerk_segments', { p_work_order_id: order.id }),
  ]);
  const shapeRows = [
    ...(shapesRes.data ?? []).map(r => ({ code: r.gerk_code, geojson: r.geojson })),
    ...(segmentsRes.data ?? []).map(r => ({ code: r.gerk_code, geojson: r.segment_geojson })),
  ];

  for (const row of shapeRows) {
    if (!row.geojson) continue;
    try {
      const layer = window.L.geoJSON(row.geojson, { style: { color: '#1c4592', weight: 2, fillOpacity: .25 } }).addTo(map);
      layer.bindTooltip(String(row.code));
      const layerBounds = layer.getBounds();
      if (layerBounds.isValid()) bounds.push(layerBounds);
    } catch { /* Ignore malformed geometry and keep the list usable. */ }
  }
  if (bounds.length) {
    const combined = bounds.reduce((result, bound) => result.extend(bound), window.L.latLngBounds([]));
    map.invalidateSize();
    map.fitBounds(combined, { padding: [32, 32], maxZoom: 16 });
  } else {
    els.mapHint.textContent = 'Za te GERK-e ni najdena geometrija.';
  }
  setTimeout(() => map?.invalidateSize(), 50);
}

function renderAll() {
  renderCards();
  renderCalendar();
}

// app.js's switchTab() owns showing/hiding #panelPlaniranje itself (same as
// the other two tabs) — this module only needs to know when it *becomes*
// visible for the first time, to lazy-load its data. A second, independent
// click listener on the same button is fine; it doesn't touch app.js's own.
els.tab.addEventListener('click', loadPlanningData);

els.prev.addEventListener('click', () => { calendarDate = new Date(calendarDate.getFullYear(), calendarDate.getMonth() - 1, 1); renderCalendar(); });
els.next.addEventListener('click', () => { calendarDate = new Date(calendarDate.getFullYear(), calendarDate.getMonth() + 1, 1); renderCalendar(); });
els.today.addEventListener('click', () => { calendarDate = new Date(); renderCalendar(); });
els.from.addEventListener('change', () => {
  if (els.from.value && els.to.value && els.from.value > els.to.value) els.to.value = els.from.value;
  if (els.from.value) calendarDate = parseDate(els.from.value);
  renderCalendar();
});
els.to.addEventListener('change', () => {
  if (els.from.value && els.to.value && els.to.value < els.from.value) els.from.value = els.to.value;
  renderCalendar();
});
els.operatorFilterButton.addEventListener('click', () => {
  const isOpen = !els.operatorFilterMenu.hidden;
  els.operatorFilterMenu.hidden = isOpen;
  els.operatorFilterButton.setAttribute('aria-expanded', String(!isOpen));
});
els.operatorFilterMenu.addEventListener('change', event => {
  if (!event.target.matches('input[type="checkbox"]')) return;
  if (event.target.checked) selectedOperators.add(event.target.value);
  else selectedOperators.delete(event.target.value);
  renderOperatorFilter();
  renderAll();
});
document.addEventListener('click', event => {
  if (!event.target.closest('.operator-filter')) {
    els.operatorFilterMenu.hidden = true;
    els.operatorFilterButton.setAttribute('aria-expanded', 'false');
  }
});
els.modalClose.addEventListener('click', closeOrderModal);
els.modal.addEventListener('click', event => { if (event.target === els.modal) closeOrderModal(); });
els.list.addEventListener('change', event => { if (event.target.matches('input')) syncSelectionSummary(); });
els.selectAll.addEventListener('change', () => {
  els.list.querySelectorAll('input').forEach(input => { input.checked = els.selectAll.checked; });
  syncSelectionSummary();
});
els.save.addEventListener('click', saveSelection);
document.addEventListener('keydown', event => {
  if (event.key === 'Delete' && selectedPlanId && els.modal.hidden) removeOrderFromCalendar(selectedPlanId);
  if (event.key === 'Escape' && !els.modal.hidden) closeOrderModal();
});
