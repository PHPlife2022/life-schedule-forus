-- 約局手帳 Supabase 資料庫設定
-- 使用方式:Supabase 後台 → SQL Editor → New query → 貼上整份 → Run
-- 可以重複執行,不會重複建立。

-- 1. 每個人的資料(名字、欄位設定)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 20),
  cols jsonb not null default '{}'::jsonb,
  last_import jsonb,
  created_at timestamptz not null default now()
);

-- 2. 活動紀錄(行事曆活動與劇本殺/桌遊/密室紀錄共用)
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references public.profiles(id) on delete cascade,
  d date not null,
  slot smallint not null default 0 check (slot between 0 and 2),
  cat text not null,
  title text not null check (char_length(title) between 1 and 80),
  genre text,
  shop text,
  price numeric,
  gm text,
  members text,
  review text,
  hide boolean not null default false,
  x jsonb not null default '{}'::jsonb,
  imp text,
  created_at timestamptz not null default now()
);

-- 2b. 後續更新新增的欄位(可重複執行)
alter table public.profiles add column if not exists settings jsonb not null default '{}'::jsonb;
alter table public.events add column if not exists tm text;
alter table public.events add column if not exists priv boolean not null default false;
alter table public.events drop constraint if exists events_cat_check;

create index if not exists events_owner_d_idx on public.events (owner, d);

-- 3. 權限規則(Row Level Security)
--    所有登入的人都能讀取;只有本人能新增、修改、刪除自己的資料。
alter table public.profiles enable row level security;
alter table public.events enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.events to authenticated;

drop policy if exists "profiles_read" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "events_read" on public.events;
drop policy if exists "events_insert_own" on public.events;
drop policy if exists "events_update_own" on public.events;
drop policy if exists "events_delete_own" on public.events;

create policy "profiles_read" on public.profiles
  for select to authenticated using (true);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- 標記為「只給自己看」(priv)的活動,只有本人讀得到
create policy "events_read" on public.events
  for select to authenticated using (owner = (select auth.uid()) or priv = false);
create policy "events_insert_own" on public.events
  for insert to authenticated with check (owner = (select auth.uid()));
create policy "events_update_own" on public.events
  for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "events_delete_own" on public.events
  for delete to authenticated using (owner = (select auth.uid()));

-- 3b. 封神榜(黑名單 / 推薦清單 / 願望清單)與表態
create table if not exists public.hall_items (
  id uuid primary key default gen_random_uuid(),
  list text not null check (list in ('black','rec','wish')),
  name text not null check (char_length(name) between 1 and 60),
  note text check (note is null or char_length(note) <= 80),
  owner uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.hall_votes (
  item uuid not null references public.hall_items(id) on delete cascade,
  voter uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('up','angry','ask')),
  created_at timestamptz not null default now(),
  primary key (item, voter)
);

-- 舊版(每人可按多種表情)改成每人每個名字只能一個表情
do $$
begin
  if (select count(*) from information_schema.key_column_usage where table_schema='public' and table_name='hall_votes' and constraint_name='hall_votes_pkey') = 3 then
    alter table public.hall_votes drop constraint hall_votes_pkey;
    alter table public.hall_votes replica identity full;
    delete from public.hall_votes a using public.hall_votes b where a.item=b.item and a.voter=b.voter and a.ctid < b.ctid;
    alter table public.hall_votes add primary key (item, voter);
    alter table public.hall_votes replica identity default;
  end if;
end $$;
alter table public.hall_items enable row level security;
alter table public.hall_votes enable row level security;
grant select, insert, update, delete on public.hall_items to authenticated;
grant select, insert, update, delete on public.hall_votes to authenticated;
drop policy if exists "hall_items_read" on public.hall_items;
drop policy if exists "hall_items_insert_own" on public.hall_items;
drop policy if exists "hall_items_update_own" on public.hall_items;
drop policy if exists "hall_items_delete_own" on public.hall_items;
drop policy if exists "hall_votes_read" on public.hall_votes;
drop policy if exists "hall_votes_insert_own" on public.hall_votes;
drop policy if exists "hall_votes_delete_own" on public.hall_votes;
drop policy if exists "hall_votes_update_own" on public.hall_votes;
create policy "hall_items_read" on public.hall_items for select to authenticated using (true);
create policy "hall_items_insert_own" on public.hall_items for insert to authenticated with check (owner = (select auth.uid()));
create policy "hall_items_update_own" on public.hall_items for update to authenticated using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "hall_items_delete_own" on public.hall_items for delete to authenticated using (owner = (select auth.uid()));
create policy "hall_votes_read" on public.hall_votes for select to authenticated using (true);
create policy "hall_votes_insert_own" on public.hall_votes for insert to authenticated with check (voter = (select auth.uid()));
create policy "hall_votes_update_own" on public.hall_votes for update to authenticated using (voter = (select auth.uid())) with check (voter = (select auth.uid()));
create policy "hall_votes_delete_own" on public.hall_votes for delete to authenticated using (voter = (select auth.uid()));

-- 3c. 沒登入的人也能「瀏覽」(只讀;標記為只給自己看的活動仍然看不到)
grant usage on schema public to anon;
grant select on public.profiles, public.events, public.hall_items, public.hall_votes to anon;
drop policy if exists "profiles_read_anon" on public.profiles;
drop policy if exists "events_read_anon" on public.events;
drop policy if exists "hall_items_read_anon" on public.hall_items;
drop policy if exists "hall_votes_read_anon" on public.hall_votes;
create policy "profiles_read_anon" on public.profiles for select to anon using (true);
create policy "events_read_anon" on public.events for select to anon using (priv = false);
create policy "hall_items_read_anon" on public.hall_items for select to anon using (true);
create policy "hall_votes_read_anon" on public.hall_votes for select to anon using (true);

-- 4. 開啟即時同步(別人新增或修改後,你的畫面會自動更新)
do $$
begin
  begin
    alter publication supabase_realtime add table public.profiles;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.events;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.hall_items;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.hall_votes;
  exception when duplicate_object then null;
  end;
end $$;

-- ============================================================
-- 5. 願望清單(取代潘朵拉的寶盒)與管理員
--    劇本/密室:名字、工作室、價錢、需要人數、目前預定人員、預定年月、備註
--    桌遊:名字、需要人數、備註
--    愛心:每個帳號對每個項目可填 1~5 顆,愛心總數最高的排最前面
--    舊的 hall_items / hall_votes 資料表不會被刪除,只是網站不再使用。
-- ============================================================

-- 5a. 管理員判斷(依登入的 Google 信箱;信箱由 Google 驗證,無法偽造)
create or replace function public.is_admin()
returns boolean
language sql stable
as $$
  select lower(coalesce((select auth.jwt() ->> 'email'), '')) = 'classroom078087@gmail.com'
$$;
grant execute on function public.is_admin() to authenticated, anon;

-- 5b. 資料表
create table if not exists public.wish_items (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('script','escape','board')),
  name text not null check (char_length(name) between 1 and 60),
  shop text check (shop is null or char_length(shop) <= 40),
  price numeric check (price is null or price >= 0),
  players text check (players is null or char_length(players) <= 20),
  booked text check (booked is null or char_length(booked) <= 100),
  booked_ym text check (booked_ym is null or booked_ym ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  note text check (note is null or char_length(note) <= 200),
  owner uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.wish_hearts (
  item uuid not null references public.wish_items(id) on delete cascade,
  voter uuid not null references public.profiles(id) on delete cascade,
  level smallint not null check (level between 1 and 5),
  created_at timestamptz not null default now(),
  primary key (item, voter)
);

-- 5c. 權限:所有人可看;登入者可新增;本人或管理員可編輯、刪除
alter table public.wish_items enable row level security;
alter table public.wish_hearts enable row level security;
grant select, insert, update, delete on public.wish_items to authenticated;
grant select, insert, update, delete on public.wish_hearts to authenticated;
grant select on public.wish_items, public.wish_hearts to anon;

drop policy if exists "wish_items_read" on public.wish_items;
drop policy if exists "wish_items_read_anon" on public.wish_items;
drop policy if exists "wish_items_insert_own" on public.wish_items;
drop policy if exists "wish_items_update_own_or_admin" on public.wish_items;
drop policy if exists "wish_items_delete_own_or_admin" on public.wish_items;
drop policy if exists "wish_hearts_read" on public.wish_hearts;
drop policy if exists "wish_hearts_read_anon" on public.wish_hearts;
drop policy if exists "wish_hearts_insert_own" on public.wish_hearts;
drop policy if exists "wish_hearts_update_own" on public.wish_hearts;
drop policy if exists "wish_hearts_delete_own_or_admin" on public.wish_hearts;

create policy "wish_items_read" on public.wish_items for select to authenticated using (true);
create policy "wish_items_read_anon" on public.wish_items for select to anon using (true);
create policy "wish_items_insert_own" on public.wish_items for insert to authenticated
  with check (owner = (select auth.uid()));
create policy "wish_items_update_own_or_admin" on public.wish_items for update to authenticated
  using (owner = (select auth.uid()) or public.is_admin())
  with check (owner = (select auth.uid()) or public.is_admin());
create policy "wish_items_delete_own_or_admin" on public.wish_items for delete to authenticated
  using (owner = (select auth.uid()) or public.is_admin());

create policy "wish_hearts_read" on public.wish_hearts for select to authenticated using (true);
create policy "wish_hearts_read_anon" on public.wish_hearts for select to anon using (true);
create policy "wish_hearts_insert_own" on public.wish_hearts for insert to authenticated
  with check (voter = (select auth.uid()));
create policy "wish_hearts_update_own" on public.wish_hearts for update to authenticated
  using (voter = (select auth.uid())) with check (voter = (select auth.uid()));
create policy "wish_hearts_delete_own_or_admin" on public.wish_hearts for delete to authenticated
  using (voter = (select auth.uid()) or public.is_admin());

-- 5d. 即時同步
do $$
begin
  begin
    alter publication supabase_realtime add table public.wish_items;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.wish_hearts;
  exception when duplicate_object then null;
  end;
end $$;

-- ============================================================
-- 6. 發展目標與學習進度(只有本人看得到,連朋友和管理員都讀不到)
--    goals:各領域與短中長期目標、要增進的能力
--    learn:每日 / 每週 / 每月 / 每年任務與完成紀錄
-- ============================================================
create table if not exists public.growth_data (
  owner uuid primary key references public.profiles(id) on delete cascade,
  goals jsonb not null default '{}'::jsonb,
  learn jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.growth_data enable row level security;
grant select, insert, update, delete on public.growth_data to authenticated;
drop policy if exists "growth_read_own" on public.growth_data;
drop policy if exists "growth_insert_own" on public.growth_data;
drop policy if exists "growth_update_own" on public.growth_data;
drop policy if exists "growth_delete_own" on public.growth_data;
create policy "growth_read_own" on public.growth_data for select to authenticated using (owner = (select auth.uid()));
create policy "growth_insert_own" on public.growth_data for insert to authenticated with check (owner = (select auth.uid()));
create policy "growth_update_own" on public.growth_data for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "growth_delete_own" on public.growth_data for delete to authenticated using (owner = (select auth.uid()));
do $$
begin
  begin
    alter publication supabase_realtime add table public.growth_data;
  exception when duplicate_object then null;
  end;
end $$;
