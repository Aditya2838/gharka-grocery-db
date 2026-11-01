-- GHARKA SUPABASE SETUP
-- Run this entire script in Supabase > SQL Editor.
-- Then create two Auth users (Mom and Dad) and attach them to one family using the instructions in README.

create extension if not exists pgcrypto;

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'GharKa Family',
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  role text not null check (role in ('mom','dad')),
  display_name text not null
);

create table if not exists public.grocery_lists (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  month_key text not null,
  created_by uuid not null references auth.users(id),
  sent_at timestamptz,
  overall_voice_path text,
  created_at timestamptz not null default now(),
  unique(family_id, month_key)
);

create table if not exists public.grocery_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.grocery_lists(id) on delete cascade,
  name text not null,
  category text not null default 'Other',
  quantity text not null,
  priority text not null default 'Essential',
  status text not null default 'pending' check (status in ('pending','purchased')),
  price numeric(10,2) not null default 0,
  voice_path text,
  sent_to_dad boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists grocery_lists_family_month_idx on public.grocery_lists(family_id, month_key);
create index if not exists grocery_items_list_idx on public.grocery_items(list_id);

-- Family membership helper (SECURITY DEFINER avoids recursive RLS on profiles).
create or replace function public.current_family_id()
returns uuid language sql stable security definer set search_path = public
as $$ select family_id from public.profiles where id = auth.uid() limit 1 $$;

create or replace function public.current_family_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() limit 1 $$;

alter table public.families enable row level security;
alter table public.profiles enable row level security;
alter table public.grocery_lists enable row level security;
alter table public.grocery_items enable row level security;

drop policy if exists "family members read family" on public.families;
create policy "family members read family" on public.families for select to authenticated
using (id = public.current_family_id());

drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile" on public.profiles for select to authenticated
using (id = auth.uid());

drop policy if exists "family members read lists" on public.grocery_lists;
create policy "family members read lists" on public.grocery_lists for select to authenticated
using (family_id = public.current_family_id());

drop policy if exists "mom creates lists" on public.grocery_lists;
create policy "mom creates lists" on public.grocery_lists for insert to authenticated
with check (family_id = public.current_family_id() and created_by = auth.uid() and public.current_family_role() = 'mom');

drop policy if exists "mom updates lists" on public.grocery_lists;
create policy "mom updates lists" on public.grocery_lists for update to authenticated
using (family_id = public.current_family_id() and public.current_family_role() = 'mom')
with check (family_id = public.current_family_id() and public.current_family_role() = 'mom');

drop policy if exists "family reads grocery items" on public.grocery_items;
create policy "family reads grocery items" on public.grocery_items for select to authenticated
using (
  exists (select 1 from public.grocery_lists l
    where l.id = list_id and l.family_id = public.current_family_id()
    and (
      public.current_family_role() = 'mom'
      or (public.current_family_role() = 'dad' and l.sent_at is not null and sent_to_dad = true)
    ))
);

drop policy if exists "mom inserts grocery items" on public.grocery_items;
create policy "mom inserts grocery items" on public.grocery_items for insert to authenticated
with check (
  public.current_family_role() = 'mom'
  and exists (select 1 from public.grocery_lists l where l.id = list_id and l.family_id = public.current_family_id())
);

drop policy if exists "family updates grocery items" on public.grocery_items;
create policy "family updates grocery items" on public.grocery_items for update to authenticated
using (
  exists (select 1 from public.grocery_lists l
    where l.id = list_id and l.family_id = public.current_family_id()
    and (public.current_family_role() = 'mom' or (public.current_family_role() = 'dad' and l.sent_at is not null and sent_to_dad)))
)
with check (
  exists (select 1 from public.grocery_lists l
    where l.id = list_id and l.family_id = public.current_family_id()
    and (public.current_family_role() = 'mom' or (public.current_family_role() = 'dad' and l.sent_at is not null and sent_to_dad)))
);

drop policy if exists "mom deletes grocery items" on public.grocery_items;
create policy "mom deletes grocery items" on public.grocery_items for delete to authenticated
using (
  public.current_family_role() = 'mom'
  and exists (select 1 from public.grocery_lists l where l.id = list_id and l.family_id = public.current_family_id())
);

-- Restrict Dad's item updates to purchase fields only.
create or replace function public.guard_grocery_item_update()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if public.current_family_role() = 'dad' then
    if new.name is distinct from old.name
      or new.category is distinct from old.category
      or new.quantity is distinct from old.quantity
      or new.priority is distinct from old.priority
      or new.voice_path is distinct from old.voice_path
      or new.list_id is distinct from old.list_id
      or new.sent_to_dad is distinct from old.sent_to_dad then
      raise exception 'Dad can only update purchase status and price';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists guard_grocery_item_update on public.grocery_items;
create trigger guard_grocery_item_update before update on public.grocery_items
for each row execute function public.guard_grocery_item_update();

-- Private audio bucket. Files are stored under: family_id/list_id/filename
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('grocery-voice','grocery-voice',false,15728640,
  array['audio/webm','audio/mp4','audio/ogg','audio/mpeg','audio/wav'])
on conflict (id) do update set public=false, file_size_limit=15728640;

drop policy if exists "family members upload voice notes" on storage.objects;
create policy "family members upload voice notes" on storage.objects for insert to authenticated
with check (
  bucket_id = 'grocery-voice'
  and (storage.foldername(name))[1] = public.current_family_id()::text
);

drop policy if exists "family members read voice notes" on storage.objects;
create policy "family members read voice notes" on storage.objects for select to authenticated
using (
  bucket_id = 'grocery-voice'
  and (storage.foldername(name))[1] = public.current_family_id()::text
);

drop policy if exists "family members delete voice notes" on storage.objects;
create policy "family members delete voice notes" on storage.objects for delete to authenticated
using (
  bucket_id = 'grocery-voice'
  and (storage.foldername(name))[1] = public.current_family_id()::text
);

grant usage on schema public to authenticated;
grant select on public.profiles, public.families, public.grocery_lists, public.grocery_items to authenticated;
grant insert, update, delete on public.grocery_items to authenticated;
grant insert, update on public.grocery_lists to authenticated;
