# WorkTracker — Proagrar

Mobile-first PWA for logging tractor operator work hours. Built for Proagrar d.o.o., Slovenia.

---

## What it does

Operators log in on their phone and record work entries:

- **Date** of work
- **Start / end time** (15-minute intervals)
- **GERK number** — the Slovenian agricultural field identifier. Autocompletes from the field registry already stored in the shared Proagrar database (ProApp). Freeform 7-digit entry also accepted.
- **Description** — optional short note

The app shows a summary (total entries, hours today, number of distinct fields) and a list of all entries. Two view modes: card view and compact table view (default).

Every write operation (insert, update, delete) is captured by a Supabase database trigger into `work_log_audit` for a full audit trail.

---

## Tech stack

| Layer | What |
|---|---|
| Frontend | Vanilla JS (ES modules), HTML, CSS — no framework |
| Auth | Supabase Auth (email + password) |
| Database | Supabase (PostgreSQL) — shared project with ProApp |
| Hosting | Static files — deployable anywhere (Vercel, Netlify, GitHub Pages) |
| Offline | PWA with service worker (network-first for HTML/JS, cache-first for assets) |

---

## Project structure

```
WorkTrackerApp/
├── index.html          # Login page
├── app.html            # Main app (shown after login)
├── app.js              # All app logic
├── auth.js             # Login form logic
├── style.css           # All styles (mobile-first, CSS variables)
├── config.js           # Supabase URL + anon key
├── manifest.json       # PWA manifest
├── sw.js               # Service worker
├── icons/
│   └── icon.svg        # App icon (tractor, Proagrar blue)
└── supabase/
    ├── schema.sql                     # Full DB schema — run once on a fresh project
    ├── operators.sql                  # Operator management functions (create/delete/list)
    └── migration_field_read_access.sql # RLS: lets operators read FIELD + CUSTOMER tables
```

---

## Database tables

All in the shared Supabase project used by both WorkTracker and ProApp.

| Table | Description |
|---|---|
| `public.profiles` | One row per operator — full name, role. Auto-created on first login via trigger. |
| `public.work_logs` | Work entries. RLS: operators see only their own rows. |
| `public.work_log_audit` | Immutable audit log — every insert/update/delete on `work_logs` is recorded here by a DB trigger. Operators can read their own audit rows but cannot write. |
| `FIELD` *(ProApp)* | Field registry with GERK codes, names, areas. Read by WorkTracker for autocomplete. |
| `B_FIELD_X_CUSTOMER` *(ProApp)* | Links fields to customers (partners). Used to show partner name in GERK autocomplete. |
| `CUSTOMER` *(ProApp)* | Customer/partner records. |

---

## Setup — fresh install

### 1. Supabase project

WorkTracker shares the same Supabase project as ProApp. You need the project URL and anon key.

Update `config.js`:

```js
export const SUPABASE_URL      = 'https://YOUR_PROJECT.supabase.co';
export const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

### 2. Database schema

In Supabase Dashboard → SQL Editor, run in order:

1. `supabase/schema.sql` — creates `profiles`, `work_logs`, `work_log_audit`, triggers, RLS policies
2. `supabase/operators.sql` — creates helper functions to manage operators
3. `supabase/migration_field_read_access.sql` — grants read access to `FIELD`, `B_FIELD_X_CUSTOMER`, `CUSTOMER` for authenticated users

### 3. Create an operator

In Supabase SQL Editor:

```sql
select public.create_operator('ime@proagrar.si', 'geslo123', 'Ime Priimek');
```

### 4. Serve the app

The app must be served over HTTP (not opened as a `file://` URL) for ES modules and the service worker to work correctly.

**Quickest option — VS Code Live Server:**
1. Install the [Live Server extension](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer)
2. Right-click `index.html` → Open with Live Server
3. Access on phone: `http://<your-pc-ip>:5500`

**Or deploy to Vercel / Netlify:**  
Drag and drop the folder — no build step needed, it's pure static HTML/JS.

---

## Want to test it?

If you want to test the app without setting up a database, ask the project owner (Matej) for a test operator account on the existing Supabase project. You can then open the deployed version or run it locally with Live Server pointing at the existing `config.js`.

---

## Known limitations / next steps

- No admin panel — operators are created manually via SQL (`create_operator()`)
- No role-based views yet — a manager/admin role exists in `profiles.role` but the app doesn't use it
- GERK autocomplete requires running `migration_field_read_access.sql`; without it, the field still accepts freeform 7-digit input
- App is Slovenian-language only
