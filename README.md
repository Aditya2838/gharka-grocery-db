# GharKa — Supabase + GitHub Pages

This build adds:
- Real email/password sign-in with Supabase Auth
- Mom and Dad roles loaded from `profiles`
- Shared monthly grocery list in Postgres
- Mom's individual voice notes on grocery items
- Mom's overall voice message for the shopping trip
- Private audio uploads to Supabase Storage
- Dad playback using temporary signed URLs
- Realtime refresh for list and item changes
- Responsive layout for phone, tablet and desktop

## 1. Create Supabase project
Create a project at https://supabase.com/dashboard.

## 2. Run database setup
Open SQL Editor > New query. Paste and run `supabase-schema.sql`.

## 3. Create Mom and Dad login accounts
In Supabase Dashboard > Authentication > Users, create two users:
- Mom's email and password
- Dad's email and password

Confirm/copy each user's UUID from the Users page.

In SQL Editor, run this (replace the UUIDs and names):
```sql
insert into public.families (name) values ('Our Family') returning id;
```
Copy the returned family UUID, then run:
```sql
insert into public.profiles (id, family_id, role, display_name) values
('MOM_AUTH_USER_UUID', 'FAMILY_UUID', 'mom', 'Mom'),
('DAD_AUTH_USER_UUID', 'FAMILY_UUID', 'dad', 'Dad');
```
Use the exact Auth user UUIDs. Do not share passwords.

## 4. Configure the frontend
Open Supabase > Project Settings > API. Copy:
- Project URL
- anon / publishable public key (NOT service_role / secret key)

Edit `supabase-config.js`:
```js
window.GHARKA_SUPABASE_URL = "https://YOURPROJECT.supabase.co";
window.GHARKA_SUPABASE_ANON_KEY = "YOUR_PUBLIC_ANON_KEY";
```
The anon key is designed for browser use only when RLS is enabled. Never put the service_role key in the website or GitHub.

## 5. Upload to GitHub Pages
Upload these files to the ROOT of your existing repository:
- `index.html`
- `supabase-config.js`
- `supabase-schema.sql` (optional to keep in repo; it contains no secret)

Commit changes. Keep the repository public only if you are comfortable with the website source being visible. The grocery data and audio remain protected by Supabase Auth + RLS + private Storage.

Enable/keep GitHub Pages: Settings > Pages > Deploy from branch > `main` > `/(root)`.

## 6. Enable Realtime
In Supabase Dashboard, open Database > Publications (or Realtime settings) and make sure `grocery_lists` and `grocery_items` are enabled in the `supabase_realtime` publication. This allows Mom's send action and Dad's purchase updates to refresh on the other phone.

## 7. Test
1. Open the GitHub Pages URL over HTTPS.
2. Sign in as Mom, add a grocery, record a short voice note, save it.
3. Record an overall voice note and save it.
4. Press Send to Dad.
5. Open the same URL on Dad's phone and sign in as Dad.
6. Confirm the item and both audio playback controls appear.
7. Mark an item purchased and enter the price.

## Notes / limitations
- Microphone recording requires HTTPS and browser microphone permission. GitHub Pages uses HTTPS.
- Browser support depends on MediaRecorder codecs. Current Chrome and Safari should work; the app chooses a supported audio MIME type.
- Audio uploads are limited to 15 MB per file in the provided bucket configuration.
- Signed audio URLs expire after one hour; the app creates fresh signed URLs when loading the list.
- This app currently maintains one list per family per calendar month.
- The frontend does not transcribe or translate voice. It stores Mom's original recording, including Telugu-English mixed speech.
- Do not commit passwords, service-role keys, or private credentials.
