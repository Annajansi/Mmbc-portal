-- ============================================================
--  Moon Millennium Client Portal — database schema
--  Run this once in Supabase → SQL Editor → New query → Run.
-- ============================================================

-- ---------- TABLES ----------

-- Agency admins (your team). Bootstrapped manually after first sign-in (see README).
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- Client companies (Verde Botanicals, Orbit Finance, ...)
create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  company text not null,
  contact_name text,
  initials text,
  created_at timestamptz default now()
);

-- Maps a logged-in user to their client company
create table if not exists client_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  client_id uuid not null references clients(id) on delete cascade
);

-- Pending invites: admin sets email→client; user gets linked on first sign-in
create table if not exists client_invites (
  email text primary key,
  client_id uuid not null references clients(id) on delete cascade
);

-- Projects / engagements
create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  name text not null,
  service text,                 -- Brand Strategy, Identity & Logo, Packaging, Digital & Web, ...
  status text default 'active', -- active | review | complete
  next_review date,
  updated_at timestamptz default now()
);

-- Deliverables (file links shown to the client)
create table if not exists deliverables (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  project_id uuid references projects(id) on delete set null,
  title text not null,
  file_url text,
  awaiting_review boolean default true,
  created_at timestamptz default now()
);

-- Activity feed
create table if not exists activity (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  title text not null,
  detail text,
  created_at timestamptz default now()
);

-- Portfolio / past work (agency-wide, shown to everyone)
create table if not exists portfolio (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  label text,                   -- short name shown on the thumbnail
  category text default 'identity', -- identity | packaging | digital | campaign
  year_text text,
  sort int default 0,
  created_at timestamptz default now()
);

-- Quote requests submitted from the portal
create table if not exists quotes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references clients(id) on delete set null,
  name text, email text, company text,
  service text, budget text, timeline text, message text,
  created_at timestamptz default now()
);

-- ---------- HELPER FUNCTIONS (run as owner, so they bypass RLS safely) ----------

create or replace function is_admin() returns boolean
language sql security definer stable as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

create or replace function my_client_id() returns uuid
language sql security definer stable as $$
  select client_id from client_users where user_id = auth.uid();
$$;

grant execute on function is_admin() to authenticated, anon;
grant execute on function my_client_id() to authenticated, anon;

-- ---------- AUTO-LINK NEW USERS TO THEIR CLIENT ON SIGN-UP ----------

create or replace function handle_new_user() returns trigger
language plpgsql security definer as $$
begin
  insert into client_users (user_id, client_id)
  select new.id, ci.client_id
  from client_invites ci
  where lower(ci.email) = lower(new.email)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- ROW LEVEL SECURITY ----------

alter table admins        enable row level security;
alter table clients       enable row level security;
alter table client_users  enable row level security;
alter table client_invites enable row level security;
alter table projects      enable row level security;
alter table deliverables  enable row level security;
alter table activity      enable row level security;
alter table portfolio     enable row level security;
alter table quotes        enable row level security;

-- admins / client_users / client_invites : admin-only
create policy admin_all_admins on admins for all using (is_admin()) with check (is_admin());
create policy admin_all_cu on client_users for all using (is_admin()) with check (is_admin());
create policy admin_all_ci on client_invites for all using (is_admin()) with check (is_admin());

-- clients : a client sees their own row; admins see/manage all
create policy clients_read on clients for select using (id = my_client_id() or is_admin());
create policy clients_write on clients for all using (is_admin()) with check (is_admin());

-- projects / deliverables / activity : client reads own; admin manages all
create policy proj_read on projects for select using (client_id = my_client_id() or is_admin());
create policy proj_write on projects for all using (is_admin()) with check (is_admin());

create policy del_read on deliverables for select using (client_id = my_client_id() or is_admin());
create policy del_write on deliverables for all using (is_admin()) with check (is_admin());

create policy act_read on activity for select using (client_id = my_client_id() or is_admin());
create policy act_write on activity for all using (is_admin()) with check (is_admin());

-- portfolio : everyone logged-in reads; admin manages
create policy port_read on portfolio for select using (auth.uid() is not null);
create policy port_write on portfolio for all using (is_admin()) with check (is_admin());

-- quotes : any logged-in user can submit; only admins read
create policy quote_insert on quotes for insert with check (auth.uid() is not null);
create policy quote_read on quotes for select using (is_admin());

-- ---------- OPTIONAL: a couple of starter portfolio rows ----------
insert into portfolio (name,label,category,year_text,sort) values
  ('Lumen Co.','Lumen','identity','2026 · Identity',1),
  ('Verde Botanicals','Verdè','packaging','2025 · Packaging',2),
  ('Orbit Finance','Orbit','digital','2025 · Digital',3),
  ('Saffron Kitchen','Saffron','campaign','2025 · Campaign',4)
on conflict do nothing;
