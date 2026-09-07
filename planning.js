import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const MONTHS = ['januar', 'februar', 'marec', 'april', 'maj', 'junij', 'julij', 'avgust', 'september', 'oktober', 'november', 'december'];
const WEEKDAYS = ['Pon', 'Tor', 'Sre', 'Čet', 'Pet', 'Sob', 'Ned'];

let orders = [];
let planEntries = [];
let selectedOrderId = null;
let selectedPlanId = null;
let selectedOperators = new Set();
let calendarDate = new Date();
let map = null;
let mapLayers = [];

const els = {
  tabs: document.querySelectorAll('.app-tab'),
  evidenca: document.getElementById('evidencaView'),
  planning: document.getElementById('planiranjeView'),
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
  modal: document.getElementById('workOrderModal'),
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

function property(source, ...names) {
  for (const name of names) {
    if (source && source[name] !== undefined && source[name] !== null) return source[name];
  }
  return null;
}

function readLastnost(...sources) {
  for (const source of sources) {
    if (!source || typeof source !== 'object') continue;
    const relation = property(source, 'gerk_lastnost', 'GERK_LASTNOST');
    const lastnost = Array.isArray(relation) ? (relation[0] ?? {}) : (relation ?? {});
    const candidates = [
      property(lastnost, 'lastnost', 'LASTNOST'),
      property(source, 'lastnost', 'LASTNOST'),
    ];

    for (const candidate of candidates) {
      if (candidate === null || candidate === undefined) continue;
      if (typeof candidate === 'string') {
        try {
          const parsed = JSON.parse(candidate);
          if (parsed && typeof parsed === 'object') return parsed;
        } catch {
          // Try the next possible source.
        }
      } else if (candidate && typeof candidate === 'object') {
        return candidate;
      }
    }
  }
  return {};
}

function readPropertyCaseInsensitive(source, key) {
  if (!source || typeof source !== 'object') return null;
  const match = Object.keys(source).find(name => name.toLowerCase() === key.toLowerCase());
  return match ? source[match] : null;
}

function readLandUse(lastnost, lastnostRecord, field) {
  const sources = [lastnost, lastnostRecord, field];
  const value = sources
    .flatMap(source => [
      readPropertyCaseInsensitive(source, 'RABA_ID'),
      readPropertyCaseInsensitive(source, 'land_use_id'),
    ])
    .find(candidate => candidate !== null && candidate !== undefined && candidate !== '');
  return value ?? 'Ni podatka';
}

function parseLastnostValue(value) {
  if (typeof value !== 'string') return value;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function parsePolygonPoints(value) {
  let points = value;
  if (typeof points === 'string') {
    try { points = JSON.parse(points); } catch { return null; }
  }
  if (!points) return null;
  if (points.type && points.coordinates) return points;
  if (points.geometry?.type && points.geometry.coordinates) return points.geometry;
  if (points.coordinates) return parsePolygonPoints(points.coordinates);
  if (!Array.isArray(points) || points.length < 3) return null;
  if (Array.isArray(points[0]) && Array.isArray(points[0][0])) points = points[0];

  const coordinates = points.map(point => {
    if (Array.isArray(point)) return [Number(point[0]), Number(point[1])];
    const longitude = point.lng ?? point.lon ?? point.longitude ?? point.x;
    const latitude = point.lat ?? point.latitude ?? point.y;
    return [Number(longitude), Number(latitude)];
  }).filter(point => point.every(Number.isFinite));
  if (coordinates.length < 3) return null;
  const first = coordinates[0];
  const last = coordinates[coordinates.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) coordinates.push([...first]);
  return { type: 'Polygon', coordinates: [coordinates] };
}

function normalizeField(link) {
  const field = property(link, 'fields', 'FIELD') ?? link;
  const lastnostRecord = property(link, 'planning_lastnost')
    ?? property(field, 'gerk_lastnost', 'GERK_LASTNOST')
    ?? property(link, 'gerk_lastnost', 'GERK_LASTNOST');
  const lastnost = readLastnost(lastnostRecord, field, link);
  const drzava = property(link, 'planning_country')
    ?? property(lastnostRecord, 'drzava', 'DRZAVA');
  const area = property(field, 'area_ha', 'AREA_HA')
    ?? readPropertyCaseInsensitive(field, 'area_ha')
    ?? readPropertyCaseInsensitive(lastnost, 'AREA')
    ?? readPropertyCaseInsensitive(field, 'AREA')
    ?? property(field, 'area', 'TOTAL_AREA');
  const type = property(link, 'planning_type') ?? readLandUse(lastnost, lastnostRecord, field);
  return {
    id: property(link, 'field_id', 'FIELD_ID') ?? property(field, 'id', 'ID'),
    code: property(link, 'gerk_code', 'GERK_CODE')
      ?? property(field, 'code', 'CODE', 'gerk', 'GERK')
      ?? 'GERK',
    name: property(field, 'name', 'NAME') ?? '',
    area,
    type: String(type),
    geometry: parsePolygonPoints(property(link, 'planning_polygon'))
      ?? property(field, 'geom', 'geometry', 'geojson', 'GEOM', 'GEOMETRY'),
    selected: false,
  };
}

function normalizeOrder(row) {
  const customer = property(row, 'customers', 'CUSTOMER') ?? {};
  const links = property(
    row,
    'delovni_nalog_gerki',
    'DELOVNI_NALOG_GERKI',
    'delovni_nalogi_gerki',
    'DELOVNI_NALOGI_GERKI'
  ) ?? [];
  return {
    id: property(row, 'id', 'ID'),
    customerName: property(customer, 'company_name', 'COMPANY_NAME', 'full_name', 'FULL_NAME') ?? `Nalog ${property(row, 'id', 'ID')}`,
    izvajalecId: property(row, 'izvajalec_id', 'IZVAJALEC_ID') ?? 'Ni izvajalca',
    status: property(row, 'status', 'STATUS'),
    fields: links.map(normalizeField).filter(field => field.id !== null),
    planDate: null,
  };
}

function getOrder(id) { return orders.find(order => String(order.id) === String(id)); }

function matchesOperator(order) {
  return !selectedOperators.size || selectedOperators.has(String(order.izvajalecId));
}

function renderOperatorFilter() {
  const operators = [...new Set(orders.map(order => String(order.izvajalecId)))].sort((left, right) => left.localeCompare(right, 'sl'));
  selectedOperators = new Set([...selectedOperators].filter(value => operators.includes(value)));
  els.operatorFilterMenu.innerHTML = operators.map(operator => `<label class="operator-filter-option">
    <input type="checkbox" value="${esc(operator)}" ${selectedOperators.has(operator) ? 'checked' : ''} />
    <span>${esc(operator)}</span>
  </label>`).join('');
  els.operatorFilterButton.textContent = selectedOperators.size ? `${selectedOperators.size} izbranih` : 'Vsi izvajalci';
}

async function loadPlanningData() {
  els.hint.textContent = 'Nalaganje delovnih nalogov ...';
  const { data, error } = await supabase
    .from('delovni_nalogi')
    .select('*, customers(*), delovni_nalogi_gerki(*, fields(*))')
    .neq('status', 'Izvedeno');

  if (error) {
    els.hint.textContent = 'Podatkovnih tabel za planiranje ni mogoče prebrati. Preverite SQL migracijo in pravice.';
    els.cards.innerHTML = `<div class="planning-error">${esc(error.message)}</div>`;
    return;
  }

  const rows = data ?? [];
  const relationIds = [...new Set(rows.flatMap(row => {
    const links = property(
      row,
      'delovni_nalogi_gerki',
      'DELOVNI_NALOGI_GERKI'
    ) ?? [];
    return links.map(link => {
      const field = property(link, 'fields', 'FIELD') ?? link;
      return property(field, 'gerk_lastnost_id', 'GERK_LASTNOST_ID');
    }).filter(id => id !== null && id !== undefined).map(String);
  }))];

  const { data: lastnosti, error: lastnostError } = relationIds.length
    ? await supabase
      .from('gerk_lastnost')
      .select('gerk_id, drzava, lastnost')
      .in('gerk_id', relationIds)
    : { data: [], error: null };

  if (lastnostError) {
    els.hint.textContent = `Tabele gerk_lastnost ni mogoče prebrati. V Supabase zaženi migration_planning.sql. (${lastnostError.message})`;
    els.cards.innerHTML = `<div class="planning-error">${esc(lastnostError.message)}</div>`;
    orders = rows.map(normalizeOrder);
    renderAll();
    return;
  }

  const lastnostByGerkId = new Map(
    (lastnosti ?? []).map(lastnost => [String(lastnost.gerk_id), lastnost])
  );
  const { data: polygons, error: polygonError } = relationIds.length
    ? await supabase
      .from('gerk_polygon')
      .select('gerk_id, polygon_points')
      .in('gerk_id', relationIds)
    : { data: [], error: null };
  if (polygonError) {
    els.hint.textContent = `Tabele gerk_polygon ni mogoče prebrati: ${polygonError.message}`;
  }
  const polygonByGerkId = new Map(
    (polygons ?? []).map(polygon => [String(polygon.gerk_id), polygon.polygon_points])
  );
  for (const row of rows) {
    const links = property(row, 'delovni_nalogi_gerki', 'DELOVNI_NALOGI_GERKI') ?? [];
    for (const link of links) {
      const field = property(link, 'fields', 'FIELD') ?? link;
      const relationId = property(field, 'gerk_lastnost_id', 'GERK_LASTNOST_ID');
      const lastnostRecord = lastnostByGerkId.get(String(relationId)) ?? null;
      link.planning_lastnost = lastnostRecord;
      link.planning_polygon = polygonByGerkId.get(String(relationId)) ?? null;
      link.planning_country = lastnostRecord?.drzava ?? lastnostRecord?.DRZAVA ?? null;
      const lastnostJson = parseLastnostValue(lastnostRecord?.lastnost);
      link.planning_type = readLandUse(lastnostJson, lastnostRecord, field);
    }
  }

  const { data: dictionary, error: dictionaryError } = await supabase
    .from('gerk_raba_id_slovar')
    .select('country, raba_id, slovenski_naziv');

  if (dictionaryError) {
    els.hint.textContent = `Šifranta gerk_raba_id_slovar ni mogoče prebrati: ${dictionaryError.message}`;
  }
  const dictionaryByKey = new Map(
    (dictionary ?? []).map(item => [
      `${String(item.country ?? '').trim().toUpperCase()}:${String(item.raba_id ?? '').trim()}`,
      String(item.slovenski_naziv ?? '').trim()
    ])
  );
  const dictionaryByCode = new Map(
    (dictionary ?? []).map(item => [String(item.raba_id ?? '').trim(), String(item.slovenski_naziv ?? '').trim()])
  );
  for (const row of rows) {
    const links = property(row, 'delovni_nalogi_gerki', 'DELOVNI_NALOGI_GERKI') ?? [];
    for (const link of links) {
      const code = String(property(link, 'planning_type') ?? '').trim();
      const country = String(property(link, 'planning_country') ?? '').trim().toUpperCase();
      const key = `${country}:${code}`;
      link.planning_type = dictionaryByKey.get(key)
        ?? dictionaryByCode.get(code)
        ?? 'Ni podatka';
    }
  }

  orders = rows.map(normalizeOrder);
  renderOperatorFilter();
  const { data: plans, error: planError } = await supabase
    .from('delovni_nalogi_planiranje')
    .select('id, delovni_nalog_id, plan_date, delovni_nalogi_planiranje_gerki(field_id)');

  planEntries = planError ? [] : (plans ?? []).map(plan => ({
    id: plan.id,
    orderId: plan.delovni_nalog_id,
    date: plan.plan_date,
    fieldIds: new Set((plan.delovni_nalogi_planiranje_gerki ?? []).map(item => String(item.field_id))),
  }));

  els.hint.textContent = orders.length ? 'Povlecite nalog na dan v koledarju.' : 'Ni odprtih delovnih nalogov.';
  renderAll();
}

function entriesForOrder(order) { return planEntries.filter(entry => String(entry.orderId) === String(order.id)); }
function plannedFieldIds(order) {
  return new Set(entriesForOrder(order).flatMap(entry => [...entry.fieldIds]));
}
function unplannedFields(order) {
  const planned = plannedFieldIds(order);
  return order.fields.filter(field => !planned.has(String(field.id)));
}
function fieldsForEntry(order, entry) {
  const selected = entry?.fieldIds ?? new Set();
  return order.fields.filter(field => selected.has(String(field.id)));
}
function isComplete(order) { return order.fields.length > 0 && unplannedFields(order).length === 0; }

function groupedAreasForFields(fields) {
  const groups = new Map();
  for (const field of fields) {
    const current = groups.get(field.type) ?? 0;
    groups.set(field.type, current + (Number(field.area) || 0));
  }
  return [...groups.entries()];
}

function groupedAreas(order) {
  return groupedAreasForFields(unplannedFields(order));
}

function renderCards() {
  const available = orders.filter(order => matchesOperator(order) && unplannedFields(order).length > 0);
  els.count.textContent = String(available.length);
  els.cards.innerHTML = available.map(order => {
    const areas = groupedAreas(order).map(([type, area]) => `<span class="area-chip"><b>${esc(type)}</b> ${formatArea(area)}</span>`).join('');
    return `<article class="work-order-card" draggable="true" data-order-id="${esc(order.id)}" role="listitem" tabindex="0">
      <div class="work-order-card-head"><h3>${esc(order.customerName)}</h3><span class="order-gerk-count">${unplannedFields(order).length} GERK</span></div>
      <div class="area-chips">${areas || '<span class="planning-hint">Brez podatka o površini</span>'}</div>
    </article>`;
  }).join('');

  els.cards.querySelectorAll('.work-order-card').forEach(card => {
    card.addEventListener('dragstart', event => event.dataTransfer.setData('text/plain', `order:${card.dataset.orderId}`));
    card.addEventListener('dblclick', () => openOrderModal(card.dataset.orderId));
    card.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') openOrderModal(card.dataset.orderId);
    });
  });
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
        return entry.date === iso && entry.fieldIds.size > 0 && order && matchesOperator(order);
      });
      const dayAreas = groupedAreasForFields(dayEntries.flatMap(entry => {
        const order = getOrder(entry.orderId);
        return order ? fieldsForEntry(order, entry) : [];
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

function renderCalendarOrder(order) {
  const entry = order;
  const sourceOrder = getOrder(entry.orderId);
  const complete = sourceOrder ? fieldsForEntry(sourceOrder, entry).length === sourceOrder.fields.length : false;
  return `<button class="calendar-order ${complete ? 'is-complete' : 'is-partial'}" draggable="true" data-order-id="${esc(entry.orderId)}" data-plan-id="${esc(entry.id)}" type="button">
    <span class="calendar-order-name"><span class="calendar-order-dot"></span>${esc(sourceOrder?.customerName ?? 'Delovni nalog')}</span>
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
  const selectedIds = unplannedFields(order).map(field => String(field.id));
  if (!selectedIds.length) return;
  await savePlan({ orderId: order.id, date, fieldIds: new Set(selectedIds) });
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
  const selected = [...entry.fieldIds].map(fieldId => ({ plan_id: plan.id, field_id: fieldId }));
  if (selected.length) await supabase.from('delovni_nalogi_planiranje_gerki').insert(selected);
  planEntries.push({ id: plan.id, orderId: entry.orderId, date: entry.date, fieldIds: new Set(entry.fieldIds) });
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
  const selectedIds = entry?.fieldIds ?? new Set();
  els.modalTitle.textContent = order.customerName;
  const sortedFields = [...order.fields].sort((left, right) => Number(selectedIds.has(String(left.id))) - Number(selectedIds.has(String(right.id))));
  els.list.innerHTML = sortedFields.map(field => {
    const selected = selectedIds.has(String(field.id));
    return `<label class="gerk-selection-row ${selected ? 'is-planned' : ''}">
    <input type="checkbox" data-field-id="${esc(field.id)}" ${selected ? 'checked' : ''} />
    <span class="gerk-selection-code">${esc(field.code)}</span>
    <span class="gerk-selection-meta">${esc(field.type)} · ${formatArea(field.area)}</span>
  </label>`;
  }).join('');
  els.modal.hidden = false;
  document.body.style.overflow = 'hidden';
  syncSelectionSummary();
  renderMap(order);
}

function closeOrderModal() {
  els.modal.hidden = true;
  document.body.style.overflow = '';
  if (map) { map.remove(); map = null; }
}

function syncSelectionSummary() {
  const order = getOrder(selectedOrderId);
  if (!order) return;
  const checked = [...els.list.querySelectorAll('input:checked')].length;
  els.summary.textContent = `${checked} od ${order.fields.length} GERK-ov izbranih`;
  els.selectAll.checked = checked > 0 && checked === order.fields.length;
  els.selectAll.indeterminate = checked > 0 && checked < order.fields.length;
}

async function saveSelection() {
  const order = getOrder(selectedOrderId);
  if (!order) return;
  const selectedIds = new Set([...els.list.querySelectorAll('input:checked')].map(input => String(input.dataset.fieldId)));
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
          const selected = [...selectedIds].map(fieldId => ({ plan_id: entry.id, field_id: fieldId }));
          const insertResult = await supabase.from('delovni_nalogi_planiranje_gerki').insert(selected);
          if (!insertResult.error) entry.fieldIds = selectedIds;
        }
        renderAll();
      }
    }
  }
  closeOrderModal();
}

function renderMap(order) {
  els.mapHint.textContent = '';
  if (!window.L) {
    els.mapHint.textContent = 'Zemljevid ni na voljo, ker knjižnice Leaflet ni mogoče naložiti.';
    return;
  }
  map = window.L.map(els.map, { zoomControl: true }).setView([46.15, 14.995], 8);
  window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '&copy; OpenStreetMap' }).addTo(map);
  mapLayers = [];
  const bounds = [];
  for (const field of order.fields) {
    let geometry = field.geometry;
    if (typeof geometry === 'string') {
      try { geometry = JSON.parse(geometry); } catch { geometry = null; }
    }
    if (!geometry) continue;
    try {
      const layer = window.L.geoJSON(geometry, { style: { color: '#1c4592', weight: 2, fillOpacity: .25 } }).addTo(map);
      layer.bindTooltip(String(field.code));
      mapLayers.push(layer);
      const layerBounds = layer.getBounds();
      if (layerBounds.isValid()) bounds.push(layerBounds);
    } catch { /* Ignore malformed geometry and keep the list usable. */ }
  }
  if (bounds.length) {
    const combined = bounds.reduce((result, bound) => result.extend(bound), window.L.latLngBounds([]));
    map.invalidateSize();
    map.fitBounds(combined, { padding: [32, 32], maxZoom: 16 });
  } else {
    els.mapHint.textContent = 'Za te GERK-e v tabeli fields ni najdena GeoJSON geometrija.';
  }
  setTimeout(() => map?.invalidateSize(), 50);
}

function renderAll() {
  renderCards();
  renderCalendar();
}

els.tabs.forEach(tab => tab.addEventListener('click', () => {
  const planning = tab.dataset.tab === 'planiranje';
  els.tabs.forEach(item => item.classList.toggle('active', item === tab));
  els.evidenca.hidden = planning;
  els.planning.hidden = !planning;
  if (planning && !orders.length) loadPlanningData();
}));
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
