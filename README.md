# WarehouseTracker — Supabase + GitHub Pages

A free, public-hosted version of WarehouseTracker. Frontend lives on GitHub Pages; backend (database + auth) lives on Supabase. Total cost: **$0**.

## What's in this folder

| File | Purpose |
|---|---|
| `database.sql` | Postgres schema + Row Level Security policies + your 298 components seeded |
| `index.html` | The whole app (UI + JS calling Supabase) |
| `config.js` | Two-line file holding your Supabase URL and anon key |
| `README.md` | This file |

That's it. No PHP, no XAMPP, no database server to run.

## How the security works (read this first)

GitHub Pages serves static files. Anyone can view-source on `index.html` and read your Supabase keys. **That is fine and intentional.** Here's why:

- **The "anon key" is public by design.** It identifies your Supabase project but grants no privileges by itself.
- **Real security lives in the database.** `database.sql` enables Row Level Security (RLS) and adds policies that say:
  - *Anyone* can `SELECT` from `products` and `inventory_items` (so viewers can read).
  - *Only authenticated users with `role = admin`* can `INSERT`, `UPDATE`, or `DELETE`.
  - `scan_logs` and `upload_history` are admin-only for both read and write.
- A malicious visitor with the anon key still cannot write — Postgres rejects the request before it touches your data.

The one key you must **never** put in `config.js` is the **`service_role`** key. That one bypasses RLS and is meant for server-side use only. We don't use it here at all.

## Setup — one-time

### Step 1: Create a Supabase project

1. Go to **<https://supabase.com>** → **Start your project** → sign in with GitHub.
2. **New project** → pick an org → name it whatever (e.g. `warehouse-tracker`) → set a database password (save it somewhere) → pick a region close to you (Southeast Asia for Philippines) → **Create project**.
3. Wait ~2 minutes for provisioning.

### Step 2: Run the schema

1. In your project, open the **SQL Editor** (left sidebar, looks like a `<>` icon).
2. **New query** → paste the entire contents of `database.sql` → click **Run**.
3. You should see "Success. No rows returned" plus messages about rows inserted. Verify with:
   ```sql
   SELECT brand, COUNT(*) FROM products GROUP BY brand;
   ```
   Expect: Carlo Gavazzi 100, Phoenix Contact 99, Siemens 99.

### Step 3: Create your admin user

The app authenticates via Supabase Auth. We need to create a user *and* tag them with `role = admin` in their JWT metadata so the RLS policies recognize them.

1. **Authentication** → **Users** → **Add user** → **Create new user**.
2. Enter your admin email and password. Tick **Auto Confirm User** so you can log in immediately without an email confirmation.
3. After creating, click the user → expand **Raw User Meta Data** section, find **App Metadata** (the read-only field above it is `User Metadata` — wrong one).

Alternative (easier): use the SQL Editor. Run this, replacing the email:

```sql
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'::jsonb
WHERE email = 'you@example.com';
```

Verify:

```sql
SELECT email, raw_app_meta_data FROM auth.users;
```

The `raw_app_meta_data` column should now include `"role": "admin"`.

### Step 4: Get your project credentials

1. **Project Settings** (gear icon) → **API**.
2. Copy:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon / public key** (a long string starting with `eyJ…`)
3. Open `config.js` in a text editor, paste both values:

   ```js
   window.SUPABASE_URL = 'https://abcdefgh.supabase.co';
   window.SUPABASE_ANON_KEY = 'eyJhbGciOi...';
   ```

### Step 5: Test locally first

You can't open `index.html` directly with `file://` — modules and Supabase auth need a real HTTP origin. Easiest way:

```bash
cd path/to/warehouse-supabase
python -m http.server 8000
```

Then open <http://localhost:8000>. The header should show `● Supabase Connected` in green. Try **Admin Login** with the email and password you set in Step 3.

If it works locally, you're ready to ship.

### Step 6: Push to GitHub Pages

1. Create a new **public** repo on GitHub (e.g. `warehouse-tracker`).
2. Push these files into it:
   ```bash
   git init
   git add index.html config.js README.md database.sql
   git commit -m "WarehouseTracker"
   git branch -M main
   git remote add origin https://github.com/YOUR-USERNAME/warehouse-tracker.git
   git push -u origin main
   ```
3. On GitHub: **Settings** → **Pages** → **Source: Deploy from a branch** → **Branch: main** → **/ (root)** → **Save**.
4. Wait ~30 seconds. Your site is live at `https://YOUR-USERNAME.github.io/warehouse-tracker/`.

### Step 7: Add your URL to Supabase's allowlist

Supabase blocks auth from unknown origins by default.

1. **Authentication** → **URL Configuration**.
2. **Site URL**: `https://YOUR-USERNAME.github.io/warehouse-tracker`
3. **Redirect URLs**: add the same URL.
4. **Save**.

Done. Visit your GitHub Pages URL and try the admin login.

## What viewers see vs. admins see

| Tab | Viewer (no login) | Admin (logged in) |
|---|---|---|
| 📊 Dashboard | ✅ Read-only | ✅ Full |
| 🔍 Scanner | ❌ Hidden | ✅ Full |
| 📦 Inventory | ✅ Read-only | ✅ Full |
| 📋 Scan Log | ❌ Hidden | ✅ Full |
| 🗄️ Database | ❌ Hidden | ✅ Full |

## Adding more admin users

Repeat Step 3 with a different email — they'll be tagged as admin and can sign in.

To make someone a viewer-only user *with their own login*: same flow but skip the `role: admin` part. They'll authenticate but the RLS policies will deny mutations.

## Things to know about the free tier

- **500 MB database** — fits ~2 million product/inventory rows, you won't hit this.
- **Unlimited API requests** — but 5 GB egress/month, more than enough.
- **50,000 monthly active users** — a real product limit.
- **Projects pause after 7 days of inactivity.** Just visit the dashboard once a week to keep it alive. If it pauses, click **Restore** in the dashboard — your data is preserved.
- **No automatic backups** on free tier. Use the **Export** button in the app periodically as a backup.

## Troubleshooting

**"Supabase not configured" banner** — `config.js` still has the placeholder values. Edit it.

**Login says "This account is not an admin"** — the user was created but the `role: admin` JWT metadata wasn't set. Re-run the `UPDATE auth.users SET raw_app_meta_data ...` SQL from Step 3.

**"new row violates row-level security policy"** — same as above. RLS is checking the JWT and not finding `role = admin`. Fix the metadata.

**Login works but no data loads** — check the browser console. If you see CORS or auth errors, make sure the **Site URL** and **Redirect URLs** in Supabase Auth Settings include your GitHub Pages URL.

**Camera scanner doesn't work on github.io** — actually, it should — `https://*.github.io` qualifies as a secure origin. If it still fails, ensure you granted camera permission in your browser.

**I want to host the catalog without exposing it publicly** — Change the products RLS policy:
```sql
DROP POLICY products_read ON public.products;
CREATE POLICY products_read ON public.products
  FOR SELECT TO authenticated USING (TRUE);
```
This restricts even reads to authenticated users. Same for `inventory_items`. Then everyone needs to log in (you can give viewers their own accounts without `role: admin`).

## Going beyond the free tier

If projects pausing is annoying or you outgrow the limits, the **Pro plan** is $25/month. For warehouse usage it's overkill — the free tier easily handles a single warehouse.
