# WorkTracker — Full Project Snapshot

**As of:** 2026-07-24
**Purpose of this document:** a complete, detailed record of what this app is, how it's built, and exactly how to recreate it from scratch — schema, RLS, functions, frontend architecture, deployment, and the reasoning behind the non-obvious decisions. Written so someone with no prior context could rebuild the whole system from this file plus the repo contents.

---

## 1. What this is

WorkTracker is an internal PWA for **Proagrar d.o.o.** (a Slovenian agricultural services company) used by tractor operators to log field work, and by admins to plan and assign that work via **work orders (Delovni Nalogi)**.

- **Live URL:** https://app.proagrar.si
- **Repo:** github.com/Proagrar/WorkTrackerApp, branch `cleanMatej` (this is the branch GitHub Pages actually serves — there is no separate build/deploy branch)
- **Users:** a handful of tractor operators, one or more supervisors, and an admin (the business owner) — small internal team, not public-facing

Two core workflows:
1. **Admin** creates a work order (customer, fields/GERKs to work, service type, cost estimates).
2. **Operator** opens that work order, presses Start to claim it, then presses Start/Stop per field to log real time spent — this produces the actual work-hour records used for payroll/reporting.

---

## 2. Tech stack

| Layer | Choice | Notes |
|---|---|---|
| Frontend | Vanilla JS (ES modules), HTML, CSS | Deliberately no framework (no React/Vue/etc.) |
| Backend | [Supabase](https://supabase.com) | Hosted Postgres + Auth + Row-Level Security + realtime (client v2, loaded from CDN, no npm install) |
| Hosting | GitHub Pages | Static file hosting, serves directly from the `cleanMatej` branch, custom domain via `CNAME` file |
| App type | PWA | `manifest.json` + `sw.js` service worker — installable, works offline for shell assets |
| Email | Resend (custom SMTP) | Used by Supabase Auth for confirmation/reset emails, configured in the Supabase dashboard (not in this repo) |

No build step. No bundler. No package.json. Files are served as-is; `app.js` is loaded as `<script type="module">` and imports the Supabase client straight from `cdn.jsdelivr.net`.

---

## 3. Repository structure

```
index.html               Login page (email/password, signup, forgot password, recovery)
app.html                 Main app page (tabs, modals) — the whole UI shell
auth.js                  Login page logic (4 modes: login/signup/reset/recovery)
app.js                   All app logic — ~1300 lines, single file, no framework
style.css                All styles, single file
config.js                Supabase URL + anon (publishable) key — safe to be public, RLS is what actually protects data
manifest.json            PWA manifest
sw.js                    Service worker — cache versioning + fetch strategy
CNAME                    GitHub Pages custom domain file (contains "app.proagrar.si")
icons/                   Proagrar_LOGO.png (header logo), Proagrar_icon.png (app icon), icon.svg
supabase/                All SQL migration files (see §6 for exact run order)
docs/                    This file, plus navodila.html (user instructions) and supabase-mcp-resume.md
README.md                Original project README (predates most of this document)
```

There is no `.github/workflows` — deploys are just "push to `cleanMatej`" and GitHub Pages picks it up automatically (confirmed by the presence of `CNAME` and absence of any Actions workflow).

---

## 4. From-scratch setup guide

### 4.1 Supabase project

1. Create a new Supabase project.
2. In **Auth → Providers**, keep email/password enabled; disable anything else (this app is email/password only, OAuth was explicitly removed at some point).
3. In **Auth → URL Configuration**, set **Site URL** to your production URL (e.g. `https://app.proagrar.si`) — **not** `localhost`, or email confirmation/reset links will point to the wrong place.
4. In **Auth → SMTP Settings**, configure a custom SMTP provider (this project uses Resend, `smtp.resend.com:465`) — Supabase's default email sending is rate-limited and not meant for production.
5. Run the SQL migrations in `supabase/` **in the order given in §6** via the SQL Editor.
6. Copy the project's URL and **anon/publishable key** (Settings → API) into `config.js`:
   ```js
   export const SUPABASE_URL      = 'https://<your-project-ref>.supabase.co';
   export const SUPABASE_ANON_KEY = '<your-anon-key>';
   ```
   This key is meant to be public (it ships in client-side code) — actual data protection comes entirely from RLS policies (§7), not from hiding this key.
7. Create your first admin user: either sign up normally through the app and then run
   ```sql
   update public.profiles set role = 'admin' where id = '<user-uuid-from-auth.users>';
   ```
   or use the `create_operator()` helper (see §6.3) from the SQL Editor.

### 4.2 Frontend

Nothing to build. Just serve the repo's static files over HTTP (any static host works for local dev — e.g. `npx serve`, Python's `http.server`, VS Code Live Server). Opening `app.html`/`index.html` via `file://` will **not** work correctly (ES module imports and the service worker both require a real origin).

### 4.3 Deployment (production)

1. Push to whatever branch GitHub Pages is configured to serve (`cleanMatej` in this repo — check **Settings → Pages** in GitHub).
2. If using a custom domain, add a `CNAME` file at the repo root containing just the domain name, and configure your DNS accordingly (GitHub's docs cover the DNS side).
3. That's the entire deploy — no build, no CI. GitHub Pages' CDN (Fastly) picks up the new files, typically within a minute.
4. **Every push must bump the version** — see §9.4. This isn't optional cosmetics: without it, the service worker fix in §9 has nothing to distinguish "new deploy" from "same deploy," and GitHub Pages' CDN caching can otherwise make it look like nothing changed.

---

## 5. Database schema (current, verified live 2026-07-24)

⚠️ **Important:** this Supabase project also hosts a large, separate CRM/agronomy schema (`CUSTOMER`, `ORDER`, `OPPORTUNITY`, `PRODUCT`, `FIELD`, `PLANT`, `FERTILIZER`, `CODE`, and their `B_*_X_*` join tables, all uppercase-named, plus a newer lowercase set `customers`/`orders`/`fields`/`reports`) — **none of that is WorkTracker's own schema.** WorkTracker only owns: `profiles`, `work_logs`, `work_log_gerks`, `work_log_audit`, `delovni_nalogi`, `delovni_nalogi_gerki`. It reads from the CRM's `customers` table (for the client/stranka picker) and `FIELD`/`B_FIELD_X_CUSTOMER`/`CUSTOMER` tables (for GERK autocomplete) — see §5.7.

### 5.1 `profiles`

| Column | Type | Default | Notes |
|---|---|---|---|
| id | uuid PK | — | FK → `auth.users.id` |
| full_name | text, nullable | — | |
| role | text | `'operator'` | values in use: `operator`, `admin`, `supervisor` |
| created_at | timestamptz | `now()` | |
| organization | text, nullable | — | used to scope supervisor visibility |

**RLS:**
- "Users can view own profile" — SELECT, `id = auth.uid()`
- "Authenticated users can view profiles" — SELECT, `auth.uid() IS NOT NULL` (i.e. any logged-in user can see all profiles — needed for operator-name lookups everywhere)
- "Users can insert own profile" — INSERT, `id = auth.uid()`
- "Users can update own profile" — UPDATE, `id = auth.uid()`

**Trigger:** `on_auth_user_created` on `auth.users` (AFTER INSERT) → `handle_new_user()` — auto-creates a profile row (`role='operator'`) when a new auth user signs up, pulling `full_name` from signup metadata if present.

### 5.2 `work_logs`

One row per operator, per work order, per day (see the unique index in §5.6.3).

| Column | Type | Default | Notes |
|---|---|---|---|
| id | uuid PK | `gen_random_uuid()` | |
| operator_id | uuid | — | FK → `auth.users.id` |
| work_date | date | `CURRENT_DATE` | |
| description | text, nullable | — | free notes |
| created_at | timestamptz | `now()` | |
| updated_at | timestamptz | `now()` | auto-updated by trigger |
| deleted_at | timestamptz, nullable | — | soft-delete column that exists but **is not actually used** — the app does hard `DELETE`, not soft-delete. Only referenced by the "Operators can view own work logs" RLS qual. |
| work_duration | integer | `0` | **minutes** — computed as the sum of this log's `work_log_gerks.duration` (which is in *seconds*, see §5.3), recomputed after every Start/Stop/edit. Not directly user-entered. |
| road_duration | integer, nullable | — | minutes, entered once per day (not per field) |
| tractor | text, nullable | — | free text, autocompleted client-side from `localStorage` |
| work_order_id | uuid, **NOT NULL** | — | FK → `delovni_nalogi.id`. Mandatory — every log must belong to a work order. |

**RLS:**
- "Operators can view own work logs" — SELECT, `operator_id = auth.uid() AND deleted_at IS NULL`
- "Operators can insert own work logs" — INSERT, `operator_id = auth.uid()`
- "Operators can update own work logs" — UPDATE, `operator_id = auth.uid()`
- "Operators can delete own work logs" — DELETE, `operator_id = auth.uid()`
- "Admins can view all logs" — SELECT, admin role check via EXISTS on `profiles`
- "Supervisors can view org logs" — SELECT (role `authenticated`), supervisor sees logs of operators sharing their `profiles.organization`

**Triggers:**
- `trg_work_logs_set_updated_at` (BEFORE UPDATE) → `set_updated_at()` — sets `updated_at = now()`
- `trg_work_logs_audit` (AFTER INSERT/UPDATE/DELETE) → `audit_work_logs()` (`SECURITY DEFINER`) — writes a full before/after row into `work_log_audit` for every change

### 5.3 `work_log_gerks`

Per-field detail within a `work_logs` day-entry. One row per GERK the operator worked on that day, for that work order.

| Column | Type | Default | Notes |
|---|---|---|---|
| id | uuid PK | `gen_random_uuid()` | |
| work_log_id | uuid | — | FK → `work_logs.id` |
| gerk_code | text | — | matched against the CRM's `FIELD.CODE` client-side for display (name/area), **no DB-level FK** — GERK codes aren't reliably unique/typed in the CRM schema |
| hectares | numeric, nullable | — | copied from the work order's planned `kolicina_ha` at the time the row is created |
| created_at | timestamptz | `now()` | |
| duration | integer, nullable | — | **seconds** (changed from minutes 2026-07-24 — see §8.6). Computed automatically: `end_time - start_time` when Stop is pressed, or manually overridden via the editable `hh:mm:ss` field. |
| completed | boolean | `false` | true once `end_time` is set; reset to `false` if Start is pressed again on that row (redo) |
| start_time | timestamptz, nullable | — | set when Start is pressed |
| end_time | timestamptz, nullable | — | set when Stop is pressed |

**RLS:**
- "Operators can view own gerks" / "insert own gerks" / "update own gerks" / "delete own gerks" — all scoped via `work_log_id IN (SELECT id FROM work_logs WHERE operator_id = auth.uid())`

Note: the UPDATE policy didn't exist originally — it was added when the live Start/Stop mechanism started doing in-place updates instead of the earlier delete-and-reinsert pattern.

### 5.4 `work_log_audit`

Append-only audit trail, written exclusively by the `audit_work_logs()` trigger — no direct INSERT/UPDATE/DELETE policies exist for normal users.

| Column | Type | Notes |
|---|---|---|
| id | bigint PK (identity) | |
| work_log_id | uuid, nullable | |
| operator_id | uuid, nullable | |
| action | text | `INSERT` / `UPDATE` / `DELETE` |
| old_data | jsonb, nullable | full row snapshot before the change |
| new_data | jsonb, nullable | full row snapshot after the change |
| changed_at | timestamptz | `now()` |
| changed_by | uuid, nullable | FK → `auth.users.id`, from `auth.uid()` at trigger time |

**RLS:** "Operators can view own audit records" — SELECT, `operator_id = auth.uid()`.

### 5.5 `delovni_nalogi` (work orders)

| Column | Type | Default | Notes |
|---|---|---|---|
| id | uuid PK | `gen_random_uuid()` | |
| stevilka | text, **unique** | `nextval('delovni_nalogi_stevilka_seq')::text` | Auto-generated bare number ("1", "2", "3", ...). Was originally `'DN-' \|\| lpad(nextval(...), 3, '0')` (e.g. "DN-001"), shortened 2026-07-24 for a narrower table column — see §8.5. Never entered manually by the admin; the create form shows it as a read-only "assigned automatically" label. |
| stranka_id | uuid, nullable | — | FK → `customers.id` (the CRM's lowercase table) |
| izvajalec | uuid, nullable | — | FK → `profiles.id` — who claimed/is assigned to this order |
| tip_storitve | text, nullable | — | CHECK: one of `Vzorčenje`, `Gnojenje`, `Setev`, `Škropljenje`, `Žetev` |
| strosek_ocena | numeric, nullable | — | estimated cost (€) |
| strosek | numeric, nullable | — | actual cost (€) |
| ure | numeric, nullable | — | legacy/unused column from the original design, superseded by per-field `duration` |
| status | text | `'Plan'` | CHECK: one of `Plan`, `V delu`, `Izvedeno`, `Izdan Račun` |
| ustvarjen | timestamptz | `now()` | created-at |
| posodobljen | timestamptz | `now()` | auto-updated by trigger |
| podrobnosti | text, nullable | — | generic free-text order-level notes (e.g. "Sampling depth: 25 cm") — deliberately generic rather than a dedicated column per service type, so it covers whatever detail a future service type needs |

**Trigger:** `trg_delovni_nalogi_posodobljen` (BEFORE UPDATE) → `update_posodobljen()` — sets `posodobljen = now()`.

**RLS (current — see §8.3 for how this evolved):**
- "Admins can manage work orders" — ALL, admin role check via EXISTS on `profiles`
- "Authenticated users can view open work orders" — SELECT (role `authenticated`), `status IN ('Plan','V delu')` — **any logged-in user can see any non-completed order**, not just ones assigned to them (needed so operators can find and claim unassigned/other-assigned orders — see §5.5.1)

#### 5.5.1 The "claim" model and its RLS consequence

Originally operators could only see work orders already assigned to them (`izvajalec = auth.uid()`). That breaks the "Start" flow: an operator can't claim an order they're not allowed to see. The RLS was widened to "any authenticated user sees all non-Izvedeno/Izdan-Račun orders" — a deliberate, explicit tradeoff:

- ✅ Any operator can browse and claim any open work order (job-board model).
- ⚠️ This also exposes `strosek`/`strosek_ocena` (cost figures) to every operator/supervisor, not just admins — Postgres RLS has no column-level filtering without a view or wrapper function, and the decision was made **not** to build that extra layer for now. If cost confidentiality ever matters, the fix is a Postgres view exposing only non-cost columns to non-admins, or a `SECURITY DEFINER` RPC that strips those fields.

### 5.6 `delovni_nalogi_gerki` (work order's planned fields)

A work order plans **multiple** fields — this table is the one-to-many child.

| Column | Type | Default | Notes |
|---|---|---|---|
| id | uuid PK | `gen_random_uuid()` | |
| delovni_nalog_id | uuid | — | FK → `delovni_nalogi.id` (no ON DELETE CASCADE was actually added — deleting a parent order would need its fields cleaned up manually or by app logic first) |
| gerk_code | text | — | same "no DB FK" caveat as §5.3 |
| kolicina_ha | numeric, nullable | — | planned hectares for this field |
| created_at | timestamptz | `now()` | |
| lokacija | text, nullable | — | free-text GPS/location for this specific field (fields within one order can be in different places) |

**RLS:**
- "Admins can manage work order fields" — ALL, admin check
- "Authenticated users can view fields of open work orders" — SELECT, mirrors the parent via `EXISTS (... delovni_nalogi dn WHERE dn.id = delovni_nalog_id AND dn.status IN ('Plan','V delu'))` (this table has no `status`/`izvajalec` of its own)

#### 5.6.1 Data note: `kolicina_ha` moved tables

`kolicina_ha` originally lived directly on `delovni_nalogi` (single hectare figure per order). Once "one order, many fields" was introduced, it moved down to this child table — no data loss occurred because only a placeholder row existed on the parent at the time.

#### 5.6.2 Data note: auto-numbering and the `DN-LEGACY` placeholder

Before `delovni_nalogi` existed, `work_logs` already had 7 real rows. Making `work_order_id` a mandatory FK required backfilling those onto *something* — a single placeholder order was created:
```sql
insert into public.delovni_nalogi (stevilka, status, tip_storitve)
values ('DN-LEGACY', 'Izvedeno', null);
```
All 7 pre-existing `work_logs` rows point at this placeholder. **This row's `id` is referenced by literal UUID** in `migration_work_logs_unique_daily.sql` (`'4f17ae46-3c22-49b8-b078-054575784e9f'`) — see §5.6.3 for why, and note this UUID is specific to *this* database; a fresh install would get a different one (or, better, skip this whole placeholder dance — see the callout in §6).

#### 5.6.3 `work_logs` uniqueness constraint

```sql
create unique index uq_work_logs_operator_order_date
    on public.work_logs (operator_id, work_order_id, work_date)
    where work_order_id <> '4f17ae46-3c22-49b8-b078-054575784e9f'; -- DN-LEGACY
```
This is a **partial** unique index, not a plain one, because two pairs of the 7 legacy rows already shared the same operator+date once backfilled onto the single `DN-LEGACY` order (they were logged before work orders existed, so nothing before that point enforced this constraint). The partial exclusion means: uniqueness is enforced for every *real* work order, just not for the historical placeholder. Guards against a real race — two GERK "Start" buttons clicked in quick succession could otherwise create two `work_logs` rows for the same day before either insert resolves (see §7.6 for the client-side half of this fix).

**On a fresh install with no legacy data:** just use a plain (non-partial) unique constraint — there's no placeholder row to exclude.

### 5.7 Tables WorkTracker reads but doesn't own (CRM schema)

| Table | Used for | Access granted |
|---|---|---|
| `customers` (lowercase) | `stranka_id` FK target; client/stranka picker + search | "Authenticated users can view customers" (SELECT, role `authenticated`, `true`) — added specifically for WorkTracker's customer picker, since the table previously only had a service-role bypass policy. **Also has an "anon can read customers" policy** (SELECT, role `anon`, `true`) that WorkTracker did **not** add — origin unclear, flagged as a finding, not yet acted on (business data — company names, contacts, VAT numbers — readable by anyone with the public anon key). |
| `FIELD`, `B_FIELD_X_CUSTOMER`, `CUSTOMER` (uppercase, legacy CRM) | GERK autocomplete (`loadFields()` reads `FIELD.CODE/NAME/TOTAL_AREA` joined through `B_FIELD_X_CUSTOMER` to `CUSTOMER.FULL_NAME`) | `migration_field_read_access.sql` added `authenticated_read` SELECT policies to all three (FIELD/B_FIELD_X_CUSTOMER had no RLS policies at all before; CUSTOMER only had an anon policy) |

Everything else in this Supabase project (`ORDER`, `OPPORTUNITY`, `PRODUCT`, `PLANT`, `FERTILIZER`, `CODE`, `reports`, `orders`, `fields`, and their join tables) belongs to a separate CRM/agronomy system sharing this Supabase project — WorkTracker never reads or writes them.

### 5.8 Functions (verbatim, current)

All `SECURITY DEFINER` functions in this project **must** explicitly revoke execute from `anon` by name — see §8.7 for why "revoke from PUBLIC" alone is not sufficient in this project.

#### `handle_new_user()` — trigger, `SECURITY DEFINER`
```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', NEW.email), 'operator')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
```
Bound to `on_auth_user_created` AFTER INSERT on `auth.users`. Execute revoked from `public, anon, authenticated` (only fires via the trigger, never called directly).

#### `set_updated_at()` — trigger, not security definer
Sets `NEW.updated_at = now()`. Bound to `work_logs`.

#### `audit_work_logs()` — trigger, `SECURITY DEFINER`
Writes INSERT/UPDATE/DELETE snapshots into `work_log_audit`. Bound to `work_logs`. ⚠️ Still shows up in security advisors as callable by `anon`/`authenticated` directly via RPC — not yet locked down (it's a trigger function, likely harmless since it references `NEW`/`OLD` and would error outside trigger context, but this was never explicitly verified — see §10 open items).

#### `update_posodobljen()` — trigger, not security definer
Sets `NEW.posodobljen = now()`. Bound to `delovni_nalogi`. Execute revoked from `public, anon, authenticated` (defensive, since it's not actually a security-sensitive function).

#### `create_operator(p_email text, p_password text, p_full_name text)` — `SECURITY DEFINER`, returns uuid
Directly inserts into `auth.users` + `auth.identities` (bypassing normal signup) and upserts a `profiles` row with `role='operator'`. **Manual admin tool, run from the SQL Editor** — never called from the app. Execute revoked from `public, anon, authenticated`.

#### `set_operator_password(p_email text, p_password text)` — `SECURITY DEFINER`
Directly updates `auth.users.encrypted_password`. Same manual-tool status. Execute revoked from `public, anon, authenticated`.

#### `delete_operator(p_email text)` — `SECURITY DEFINER`
Deletes from `auth.users` by email (cascades to `profiles`/`work_logs` via their FKs). Same manual-tool status. Execute revoked from `public, anon, authenticated`.

#### `start_work_order(p_work_order_id uuid)` — `SECURITY DEFINER`, returns void
```sql
CREATE OR REPLACE FUNCTION public.start_work_order(p_work_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.delovni_nalogi
    SET status = 'V delu', izvajalec = auth.uid()
    WHERE id = p_work_order_id AND status = 'Plan';
END;
$$;
```
**This is the only function actually called by the app itself** (via `supabase.rpc('start_work_order', ...)`), by any authenticated user — it's how "claiming" a work order works. Only touches `status`/`izvajalec`, and only fires from the `Plan` state (silently no-ops otherwise). Execute granted to `authenticated` only (see §8.7 — this needed a same-session fix after initially being anon-callable).

### 5.9 Sequences

`delovni_nalogi_stevilka_seq` — backs `delovni_nalogi.stevilka`'s default. Plain `CREATE SEQUENCE`, starts at 1, increment 1. Granted `USAGE, SELECT` to `authenticated` (needed because the client's INSERT runs as the `authenticated` role, and the column default calls `nextval()` as part of that INSERT — without the grant, the insert would fail on a permissions error before RLS even gets evaluated).

---

## 6. Migration files — exact run order

Run these against a fresh Supabase project's SQL Editor, in this order.

| # | File | What it does |
|---|---|---|
| 1 | `schema.sql` | `profiles`, `work_logs` (original shape, later altered), `work_log_audit`, `set_updated_at`/`audit_work_logs` triggers, base RLS |
| 2 | `migration_v2_new_schema.sql` | Reshapes `work_logs` (drops old time/location columns, adds `work_duration`/`road_duration`/`tractor`), creates `work_log_gerks` + its RLS, creates `handle_new_user()` + its trigger |
| 3 | `operators.sql` | `create_operator`/`set_operator_password`/`delete_operator` + all the `revoke execute ... from public, anon` statements (§8.7) |
| 4 | `migration_field_read_access.sql` | Authenticated-read RLS on the CRM's `FIELD`/`B_FIELD_X_CUSTOMER`/`CUSTOMER` (needed for GERK autocomplete) |
| 5 | `migration_work_orders.sql` | Creates `delovni_nalogi` + RLS, adds `customers` authenticated-read policy, makes `work_logs.work_order_id` a mandatory FK (with the DN-LEGACY backfill dance — **on a fresh install with zero existing `work_logs` rows, skip the backfill and just add the column `NOT NULL` directly, no placeholder needed**) |
| 6 | `migration_work_order_fields.sql` | Creates `delovni_nalogi_gerki` (multi-field-per-order), drops `delovni_nalogi.kolicina_ha` |
| 7 | `migration_work_log_gerks_duration.sql` | Adds `duration`/`completed` to `work_log_gerks` (later reinterpreted as seconds — see #14 below) |
| 8 | `migration_work_order_autonumber.sql` | Sequence + default for `stevilka` (later shortened — see #16) |
| 9 | `migration_work_order_details.sql` | Adds `delovni_nalogi.podrobnosti`, `delovni_nalogi_gerki.lokacija` |
| 10 | `seed_sample_work_order_kramar.sql` | Optional: one real sample work order (20 fields) — skip for a truly empty install |
| 11 | `migration_work_log_gerks_timestamps.sql` | Adds `start_time`/`end_time` to `work_log_gerks` + the UPDATE RLS policy that was missing |
| 12 | `migration_work_order_start_flow.sql` | `start_work_order()` RPC + widens `delovni_nalogi`/`delovni_nalogi_gerki` SELECT RLS to all authenticated users (§5.5.1) |
| 13 | `migration_fix_start_work_order_grant.sql` | **Must run immediately after #12** — fixes `start_work_order()` being callable by `anon` (§8.7) |
| 14 | `migration_work_logs_unique_daily.sql` | Partial unique index on `work_logs` (§5.6.3) — **on a fresh install, use a plain unique index instead, no partial WHERE needed** |
| 15 | `migration_work_log_gerks_duration_seconds.sql` | Reinterprets `work_log_gerks.duration` as seconds instead of minutes, recomputes existing rows (no-op on an empty table) |
| 16 | `migration_work_order_number_shorten.sql` | Changes `stevilka`'s default from `"DN-001"` style to a bare number |

If you're building fresh (no legacy data to preserve), you can collapse #5+#14's legacy-handling into simpler versions per the callouts above — the file-by-file history above is preserved as-is for accuracy against the real production database, not because every step is necessary for a green-field install.

---

## 7. Application architecture

### 7.1 Auth (`index.html` + `auth.js`)

Single page, four modes toggled by JS (no separate URLs):
- **login** — email + password
- **signup** — adds full name + confirm password, calls `supabase.auth.signUp()` with `full_name` in the user metadata (picked up by `handle_new_user()`)
- **reset** — sends a password-reset email via `supabase.auth.resetPasswordForEmail()`
- **recovery** — entered automatically when Supabase fires a `PASSWORD_RECOVERY` auth event (user clicked the emailed link); lets them set a new password via `supabase.auth.updateUser()`

Already-logged-in visitors get redirected straight to `app.html`. No OAuth (Google/Facebook were removed at some point prior to this document).

### 7.2 App shell (`app.html` + `app.js`)

- Fixed header: Proagrar logo + tiny app version string (top-left), operator name + role badge + logout (top-right).
- Two tabs, **Delovni Nalogi first** (default/active tab), **Evidenca dela second**. `boot()` loads work orders first (so the default tab isn't stuck on a spinner) then loads Evidenca dela's logs in the background.
- One FAB (bottom-right +), visible **only** on the Delovni Nalogi tab and **only** for admins — opens the "create work order" modal. It has no role on the Evidenca dela tab at all (the old "add work log manually" flow was fully removed — see §8.4).
- Three modals share the page: `formModal` (work order detail / live time tracking — repurposed from an earlier "add work log" modal, hence the id), `workOrderModal` (admin creates a work order's plan — **create-only**, see §8.8), `deleteModal` (confirms deleting a log entry — the work-order variant of this was removed along with the rest of the work-order edit/delete UI, see §8.8).

### 7.3 Evidenca dela tab (history view)

- Greeting + today's date.
- Month navigation (prev/next arrows).
- 4 stat cards for the selected month: entry count, work hours, road hours, distinct GERK count (`updateStats()`).
- Log list, toggle between card view and compact table view (`renderLogsCards`/`renderLogsCompact`), scoped by role:
  - operator: own logs only
  - supervisor: logs of operators sharing their `organization`
  - admin: all logs, with an operator-name badge/column
- Each entry has a **Delete** button only — editing a past entry's live timestamps doesn't fit the Start/Stop model, so the "Uredi" (edit) path was removed entirely (§8.8).

### 7.4 Delovni Nalogi tab (work order list)

Compact table, columns: **Št.** (order number) | **Stranka** (client name) | **GERKI** (field count) | **Ha** (total planned hectares) | **Status** (colored badge). A search box next to the title filters by client name, with a dropdown of every client that appears in the currently-loaded work orders (deduplicated, sorted) — type to filter or click to pick.

Tapping any row opens the work order detail view (§7.5). Admin's Edit/Delete icon buttons that originally sat in each row were both removed per explicit request (§8.8) — admins create new orders via the FAB + `workOrderModal`, but there is currently no UI path to edit or delete an existing order's plan at all (both the UI and the underlying code for those were removed, not just hidden — see §8.8).

### 7.5 Work order detail — live time tracking (the core feature)

This is the most involved part of the app. Opened by tapping a row in the Delovni Nalogi tab (`openWorkOrderDetail(workOrder)`).

**Everything here saves immediately** — there is no "Save" button for this view (only "Zapri"/Close). Every interaction is its own `await supabase.from(...).update(...)` call.

1. **Header**: order label ("stevilka — stranka"), and a Start button that is:
   - Blue, "Start", enabled — if `status === 'Plan'`.
   - Green, "V delu", disabled — once started, showing "Izvaja: `<operator name>`" and "Skupaj: `<total time>`" below it.
   - Green, "Končan", disabled — once every field row is completed (client-computed from the rendered rows, not a separate DB status).

   Pressing Start calls the `start_work_order` RPC (§5.8), which reassigns `izvajalec` to whoever pressed it — **even if someone else was previously assigned** (explicit design choice: whoever claims it now owns it).

2. **Field rows** (`renderWorkLogGerkRows`), one per planned GERK on this order (plus any GERK today's log already has that the plan no longer lists, so re-opening never silently drops historical data):
   - Shows GERK code + field name (looked up client-side from the `fields` array, populated from the CRM's `FIELD` table) + hectares + location, on one line.
   - A **Start/Stop toggle button** (same button, text/color changes): idle → "Start" (outlined blue); running → "Stop" (solid red) with a live `HH:MM:SS` ticking clock next to it, updating every second via `setInterval`.
   - Pressing **Stop**: computes `duration = end_time - start_time` in seconds, sets `completed = true`, turns the whole row's background green, and replaces the ticking clock with an **editable** `hh:mm:ss` text field showing the recorded duration (can be manually corrected — parsed back to seconds on blur via `parseHMS()`).
   - Pressing **Start** again on an already-completed (green) row clears `end_time`/`duration`/`completed` and starts a fresh session — the escape hatch for redoing a field.
   - There is **no separate manual "completed" checkbox** — completion is entirely implied by having an `end_time`, driven by the Start/Stop toggle itself (this was a deliberate simplification once the checkbox became redundant with the live-timer model).

3. **Lazy row creation**: opening the detail view does *not* immediately create a `work_logs` row — one is only created (`ensureTodaysLog()`) the first time any Start/Stop/duration-edit/road-duration/tractor/notes field actually fires a save. This is memoized via an in-flight promise (`ensureTodaysLogPromise`) so that clicking Start on two different GERK rows in quick succession doesn't race into creating two rows before either insert resolves — reinforced at the DB level by the partial unique index (§5.6.3). A `23505` (unique violation) error from a genuine cross-tab/cross-device race is caught and resolved by re-fetching the row that won, rather than failing.

4. **Order-level fields** (road duration, tractor, notes) save on `change`/`blur`, same lazy-row-creation path, no dedicated button.

5. **`work_logs.work_duration`** is recomputed (`recomputeWorkLogDuration`) after every Stop/duration-edit — sum of all this log's `work_log_gerks.duration` (seconds), converted to minutes and rounded, kept purely so the Evidenca dela tab's existing minute-based stats code keeps working unmodified.

### 7.6 Admin: create a work order's plan (`workOrderModal`)

Separate from the live-tracking view above — this is where the *plan* itself (which fields, which customer, cost estimates, status, notes) gets defined. **Create-only**, reached via the FAB — the edit path (and its code: `woEditId`, the update-vs-insert branch, prefilling from an existing order) was removed entirely (§8.8), not just hidden. To change an existing order's plan today, there is no UI; it would need a direct SQL update or the edit feature would need to be rebuilt.

- **Stranka**: autocomplete text input against the CRM's `customers` table (loaded once, cached in the `customers` array).
- **Izvajalec**: a plain `<select>` of all profiles (not filtered by role — any user could technically be pre-assigned, though in practice this is operators).
- **Tip storitve**: fixed `<select>` matching the DB `CHECK` constraint's five values.
- **GERKI**: a repeatable row list (reusing the same `addGerkRow`/`getFormGerks` component the old work-log-entry flow used to use) — each row: GERK code (autocomplete against `fields`), hectares, free-text location. At least one required; codes are validated against the known `fields` list or a 7-digit-number fallback pattern.
- **Stroški** (estimated/actual), **Status**, **Podrobnosti** (free text).
- **Stevilka** is shown as a read-only label, never an editable field (§5.5, §8.5) — "Številka bo dodeljena samodejno ob shranjevanju" when creating.

On submit: insert/update `delovni_nalogi`, then (if editing) delete all existing `delovni_nalogi_gerki` rows for that order and re-insert the current field list wholesale (not a diff/merge).

### 7.7 Roles and permissions summary

| Role | Evidenca dela | Delovni Nalogi list | Create/edit work order plan | Claim/log time on a work order |
|---|---|---|---|---|
| operator | own logs only | sees all Plan/V delu orders | no | yes, any order (claims it via Start) |
| supervisor | logs of same-organization operators | sees all Plan/V delu orders | no | yes, any order |
| admin | all logs | sees **every** order regardless of status — the separate "Admins can manage work orders" `ALL` policy has no status filter, unlike the `authenticated`-role policy operators/supervisors rely on | yes (FAB only, in-place edit UI removed) | yes, any order |

Enforcement is at the RLS layer (§5), not just the UI — hiding a button doesn't grant/revoke anything by itself; every RLS policy listed in §5 is the actual authority.

---

## 8. Key decisions and how the design got here

A rough timeline of the reasoning, since several early designs were explicitly superseded:

### 8.1 Security-first Supabase MCP review (session start)
Connected a read-only Supabase MCP server, cross-checked live schema/RLS against what was documented, and found `create_operator`/`delete_operator`/`set_operator_password`/`handle_new_user` were callable by **anonymous, unauthenticated** users — Postgres grants `EXECUTE` to `PUBLIC` by default on new functions, and nothing had revoked it. Fixed same-session. This pattern repeated later (§8.7) — see the standing rule it produced.

### 8.2 Work orders introduced
Added `delovni_nalogi` + `delovni_nalogi_gerki` as a genuinely new feature (not present at session start) — admin-authored plans of which fields need which service, for which customer.

### 8.3 Visibility widened for the claim model
Originally operators could only see orders already assigned to them. Once "press Start to claim an unassigned order" was designed, that RLS had to widen to "any authenticated user sees any open order" — a conscious tradeoff (§5.5.1), not an oversight.

### 8.4 Live Start/Stop fully replaced manual entry
The very first version of "log time against a work order" was a single form: pick a date, type total hours, list GERKs with hectares, hit Save once. That was **entirely replaced** by the live per-field Start/Stop timer described in §7.5, once the requirement became "auto-log start/end datetime per field, in real time." The old manual entry, its "edit a past log" pathway, and the historical-log editing UI were all removed as a consequence — Delete is all that's left for history.

### 8.5 Auto-numbering
`stevilka` moved from admin-typed free text → DB-generated `"DN-001"` style → DB-generated bare number, in that order, purely for UI-density reasons (the compact table's number column kept needing to shrink as more columns were added).

### 8.6 Duration precision: minutes → seconds
`work_log_gerks.duration` started as whole minutes (matching `work_logs.work_duration`'s existing convention). Once the completed-row duration field needed to *display* as `hh:mm:ss`, minute-only precision made seconds always show `:00`, so the column was reinterpreted as seconds — with `work_logs.work_duration` still in minutes (rounded) so the older Evidenca dela stats code didn't need touching.

### 8.7 Standing rule: `SECURITY DEFINER` functions and `anon`
This exact class of bug happened **twice** in one session: `revoke execute on function ... from public;` alone does **not** lock out `anon` on this project, because Supabase's default privileges grant `EXECUTE` on new `public`-schema functions directly to `anon`/`authenticated`/`service_role` — not through the `PUBLIC` pseudo-role. The fix that actually works, every time:
```sql
revoke execute on function public.my_function(...) from public, anon;
grant execute on function public.my_function(...) to authenticated;
```
Verify with (not `information_schema.routine_privileges` — that returned empty even when `anon` clearly had access):
```sql
select p.proname, (aclexplode(p.proacl)).grantee::regrole, (aclexplode(p.proacl)).privilege_type
from pg_proc p where p.proname = '<function_name>';
```
`anon` must not appear unless the function is genuinely meant to be public.

### 8.8 UI simplification: Edit/Delete removed from work orders
Both the "Uredi" (edit) and "Izbriši" (delete) buttons on work order rows were removed per explicit request, in that order, within the same session — initially just hidden (buttons/wiring removed, underlying code left in place). During a later code-cleanup pass, once it was confirmed `openWorkOrderModal(...)`'s edit branch and the `pendingDeleteType === 'workorder'` delete-confirm branch were genuinely unreachable from any remaining button, they were removed outright rather than left as dead code: `workOrderModal` is now create-only (`woEditId` and the update-vs-insert branching are gone), and the delete-confirm flow now only ever deletes a `work_logs` row (the `pendingDeleteType` concept was removed). There is currently **no way to edit or delete an existing work order's plan** through the UI at all.

### 8.9 Tab order flipped
Delovni Nalogi and Evidenca dela swapped positions (Delovni Nalogi now first and default) per explicit request — this is also why `boot()` loads work orders before logs.

### 8.10 App versioning
A tiny version string was added under the header logo, tied to `sw.js`'s cache-busting constant, explicitly to make it obvious when a new deploy has landed (also forces installed PWAs to refresh their cached shell). The bump rule (§9.4) changed once mid-session: originally +1 per push, changed to +0.1 for normal changes / next whole number for major ones, with the counter reset to `v1.0` at that point (so version numbers before that reset — `v14`–`v17.1` — don't mean anything relative to the current `v1.x` numbering).

---

## 9. PWA / service worker details

### 9.1 Strategy
- **Supabase and jsdelivr CDN requests**: always network-first, fall back to cache only if offline.
- **`.html`/`.js` requests**: network-first, **with `cache: 'no-store'`** on the fetch call (added 2026-07-24 — see §9.3), so code changes are always picked up when online.
- **Everything else** (CSS, icons, manifest): cache-first.

### 9.2 Update mechanism
`install` calls `self.skipWaiting()`; `activate` deletes any cache key that isn't the current `CACHE` constant and calls `self.clients.claim()` — together these mean a new service worker takes over immediately (including already-open tabs) rather than waiting for every tab to close, which is the classic SW-update footgun.

### 9.3 The caching bug that prompted this section
Even with the above, deploys sometimes didn't visibly update. Root cause: the network-first `fetch()` call for HTML/JS didn't bypass the **browser's own** HTTP cache — if GitHub Pages/Fastly sent any `Cache-Control` freshness header, `fetch()` could return a stale response with no real network round-trip at all, silently defeating "network-first." Fixed by adding `{ cache: 'no-store' }` to that fetch call, plus calling `registration.update()` right after `register()` in both `index.html` and `app.html` so the browser actively checks for a new `sw.js` on every load rather than relying on its own timing.

### 9.4 Versioning convention (current rule, as of 2026-07-24)
`sw.js`'s `CACHE` constant and `app.js`'s `APP_VERSION` constant are always bumped together, before every push:
- **Normal/incremental change** → `+0.1` (e.g. `v1.2` → `v1.3`)
- **Major change/new feature** → next whole number, decimal reset (e.g. `v1.3` → `v2.0`)

Current version at the time of this document: **v1.6**.

---

## 10. Known open items / things worth revisiting

- **`anon can read` RLS policies on the CRM's `customers`/`orders`/`fields`/`reports`** (§5.7) — not created by WorkTracker's own work, origin unconfirmed, but confirmed to be a *systematic* pattern (identical policy on all four tables, not a one-off), deliberately set up rather than accidental — most likely to support a public customer-portal feature that doesn't use Supabase Auth (the `customers` table has a `portal_password` column). This is live, real data (528 customers, 4,684 fields, 427 reports as of 2026-07-24), not test rows. Sharper finding: `customers.portal_password` has exactly one populated value across all 528 rows, and it's 7 characters long — nowhere near a bcrypt hash (always 60 chars, `$2a$`/`$2b$` prefix), so it's almost certainly stored in **plaintext** and is currently readable by anyone with the public anon key. Deferred by the user ("later") but flagged as a genuinely live, concrete credential-exposure risk on the CRM/portal side, not theoretical — worth raising with whoever owns that app.
- **`audit_work_logs()`** still shows as `anon`/`authenticated`-executable in security advisors — never explicitly confirmed harmless (it's a trigger function, referencing `NEW`/`OLD`, so a direct RPC call would likely error, but "likely" isn't "verified").
- **Cost field visibility** (§5.5.1) — `strosek`/`strosek_ocena` are visible to every operator/supervisor now that work-order visibility was widened. Accepted for now; would need a view or wrapper RPC to fix properly.
- **Geofencing / auto time-tracking was explored but not built** — Slovenia's MKGP/GERK cadastral data is publicly downloadable (shapefile, via rkg.gov.si and the eprostor.gov.si WMS service) and could in principle back a point-in-polygon "operator is inside this field's boundary" check, but reliable **background** GPS tracking isn't realistic on a PWA (especially iOS) without a native app wrapper — this remains an idea, not an implementation. A more realistic middle ground discussed: an on-demand "where am I" check against the current work order's boundary, run while the app is open in the foreground.
- **`ure` column on `delovni_nalogi`** is vestigial — superseded by per-field `duration`, never removed.
- **`ON DELETE` behavior for `delovni_nalogi_gerki.delovni_nalog_id`** was never explicitly set (no CASCADE) — deleting a work order with existing field rows needs those handled first (currently: no delete button exists in the UI at all, see §8.8, so this hasn't been hit in practice).
- **`seed_test_work_orders.sql`** exists in the repo but has never actually been run against production.

---

## 11. Where to look for more

- `docs/supabase-mcp-resume.md` — the original session-resume note for the Supabase MCP connection setup.
- `docs/navodila.html` — end-user instructions (Slovenian).
- `README.md` — original project README, predates most of the above.
