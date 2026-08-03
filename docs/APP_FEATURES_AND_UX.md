# WorkTracker — Features, Roles, User Paths & UX Notes

Snapshot as of 2026-08-02. Companion to `PROJECT_SNAPSHOT.md` (schema/decisions) — this file is about what a person actually *does* in the app, per role, and where the friction is.

## 1. What the app is

A PWA for Proagrar with three surfaces:
- **`app.html`** — internal tool for operators/supervisors/admins: log field work hours against work orders, manage work orders, and (admin) manage customer crop-declaration links.
- **`index.html`** — email/password auth (login/signup/reset/recovery).
- **`deklaracija.html`** — public, no-login page where a *customer* fills in a crop-declaration form via a tokenized link.

## 2. User roles

| Role | Set via | Scope |
|---|---|---|
| `operator` | `profiles.role`, default | Own work_logs only |
| `supervisor` | `profiles.role` | Own work_logs + read-only view of all work_logs from operators in the same `organization` |
| `admin` | `profiles.role` | Everything supervisors see, plus full work-order CRUD, plus customer/declaration management |
| *(customer, no account)* | possession of a link token | One customer's own fields, for the year the link was generated for |

Role only gates **what you can see/reach in the UI** for the admin-only pieces (FAB, "Seznam strank"); the actual write protection is enforced by Postgres RLS + RPC-level `auth.uid()`/role checks, not the client.

## 3. Feature inventory

**Auth** (`index.html`/`auth.js`) — email/password login, signup w/ full name, forgot-password, password-recovery-via-email-link. No OAuth.

**Delovni Nalogi tab** (default tab on login)
- Compact table of work orders: number, client, GERK count, total ha, status badge.
- Search-by-client with autocomplete.
- Tap a row → opens the live time-tracking detail modal for that order.
- Admin only, via FAB → "+ Nov delovni nalog": create a work order — pick stranka (autocomplete), izvajalec (assign operator), tip_storitve (Vzorčenje/Gnojenje/Setev/Škropljenje/Žetev), multiple GERK rows (code autocomplete + ha + lokacija), estimated/actual cost, initial status, notes.

**Work order detail modal** (live time tracking, per work order per day)
- Date picker (default today; can pick a past date to backfill).
- "Prevzemi nalog" — claims a Plan-status order (→ status `V delu`, assigns caller as izvajalec).
- **Čas na poti (road time):** list of already-added entries, each removable; an hour/minute picker + "Dodaj" appends a new one. Summed server-side.
- **GERKI list:** one row per planned field. **Start** button stamps the current time; **Konec** stamps the end time (disabled until Start is pressed); both times shown next to their button. A pencil icon opens an inline editor (two time inputs) to correct/backfill either value.
- Traktor (free text, autocompletes from local history) and Opombe (notes).
- Every field auto-saves on change/blur — no explicit save button.

**Evidenca dela tab**
- Month navigator, 4 stat cards (entries / work hours / road hours / GERK count).
- Card or compact list view of that month's entries.
- Admin/supervisor see an operator-name badge per entry (they see multiple people's logs); operators only ever see their own.
- Delete per entry (with confirm dialog). **No edit** — correcting a past entry means going back through Delovni Nalogi to that work order and date (see UX notes).

**Seznam strank** (admin only, via FAB → "Seznam strank")
- Searchable list of all customers → tap one → detail view:
  - "Ustvari povezavo" generates a token link (language auto-derived from the customer's `country`).
  - "Kopiraj povezavo" copies it; "Pošlji e-pošto" emails it (shown only if the customer has an email; relabels to "Pošlji ponovno" once sent, with a sent-date shown).
  - List of every link generated for that customer, with created/last-used/email-sent dates.
  - Review table of what they've submitted for the current year, per field.

**Public declaration form** (`deklaracija.html`, token in URL, no login)
- Bilingual (sl/hr) per the link.
- One card per field (read-only name/GERK/area) with editable crop-this-year, crop-next-year, green cover, straw-stays, expected yield, organic fertilizer used/type/amount/unit.
- Single "Shrani" submits everything in one call; reopening the same link shows prior answers and re-saving updates them (upsert) until the link expires (~90 days default).

**Platform**: installable PWA, service worker (network-first HTML/JS, cache-first CSS/icons), version shown in header, safe-area-aware for notched phones. Layout is mobile-first with a desktop (900px+) layer added 2026-08-01 that widens the shell and turns modals into centered dialogs instead of bottom sheets.

## 4. User path per role

**Operator**
1. Log in → lands on Delovni Nalogi.
2. Find their order (or an unclaimed one) → tap it → "Prevzemi nalog" if still Plan.
3. Per field: Start → (do the work) → Konec. Add road-time lines as needed. Set tractor/notes.
4. Switch to Evidenca dela to sanity-check the month; delete a wrong entry if needed.
5. No admin surface at all — no FAB, no customer access.

**Supervisor**
- Same as operator for their own logging, **plus** read-only visibility across their organization's operators in Evidenca dela (name badges). No creation/edit powers, no FAB.

**Admin**
- Everything above, plus: create work orders (FAB), see every work_log regardless of org, and the entire Seznam strank flow (generate/copy/email declaration links, review submissions).
- Can move a work order Plan → V delu via "Prevzemi nalog," but **there is no UI path to set Izvedeno or Izdan Račun, or to edit an existing order's client/GERKs/cost after creation** — confirmed in code, the create modal has no edit call site. Today that requires a direct DB edit.

**Customer** (no account)
1. Receives a link (email or manually shared).
2. Opens it, sees their fields with whatever they last saved pre-filled.
3. Edits, saves, can return and correct anytime before expiry.

## 5. UX suggestions

Ranked by how much day-to-day friction they likely cause:

1. **No way to close out a work order.** Status only ever moves Plan → V delu via "Prevzemi nalog." Add an explicit status control (dropdown or buttons) in the detail modal so admins can mark Izvedeno / Izdan Račun without touching SQL.
2. **No edit path for an existing work order.** Wrong GERK, wrong cost estimate, wrong assigned operator — currently unfixable in-app. The create modal already has all the right fields; it just needs a second call site that pre-fills from an existing row.
3. **Fixing a past log entry is a scavenger hunt.** The mistake is spotted in Evidenca dela, but the fix is in Delovni Nalogi → find the order → change the date picker → find the field → hit the pencil. A direct "Uredi" link on each Evidenca dela entry that opens straight to that day's detail view would remove 2–3 hops.
4. **The FAB is the only admin entry point**, and it's invisible whenever a modal is open. Fine on phone; on the new wider desktop layout there's room for this to be a persistent nav item instead of a hidden floating menu — worth reconsidering now that desktop is a first-class target.
5. **Cost fields are visible to everyone**, not just admins (an accepted tradeoff from when work-order visibility was widened, not re-checked since). Worth revisiting if cost sensitivity actually matters day to day.
6. **No per-operator filter in Evidenca dela** for admins/supervisors scanning many people's entries — just month navigation today.
7. **No signal when a customer submits a declaration.** Admin has to reopen Seznam strank and manually check each customer. Even a "submitted since you last looked" badge would close the loop.
8. **No bulk link generation.** Rolling this out to many customers at once means opening each one individually. A "generate + email for everyone with an address on file" bulk action would matter a lot for initial rollout, less for steady state.
9. **Start/Konec is single-session per field per day** — pressing Start again clears the previous end time. If a field is genuinely worked in two separate sessions the same day, the first session's time is lost. Road time already supports multiple entries per day; GERK time doesn't. Worth confirming this matches how operators actually work before treating it as a non-issue.
10. **Desktop layout is "stretched mobile," not native desktop** (by deliberate choice, 2026-08-01) — same components, more breathing room. A true desktop layout (persistent sidebar, list+detail side-by-side instead of modals) is a bigger follow-up if the ROI is there.
