-- DengueWatch — Supabase (PostgreSQL) schema
--
-- Apply with:  psql "$SUPABASE_DB_URL" -f database/schema.sql
-- or paste into the Supabase SQL editor. Safe to re-run.
--
-- Ingestion writes with the service-role key, which bypasses RLS. Everything
-- else reads through anon/authenticated roles, which RLS restricts to SELECT.

create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ---------------------------------------------------------------------------
-- daily_summaries — one row per DGHS reporting day
-- ---------------------------------------------------------------------------
create table if not exists public.daily_summaries (
    id                      uuid primary key default gen_random_uuid(),
    report_date             date        not null unique,
    total_cases_24h         integer     not null check (total_cases_24h  >= 0),
    total_deaths_24h        integer     not null check (total_deaths_24h >= 0),
    total_cases_ytd         integer     check (total_cases_ytd    >= 0),
    total_deaths_ytd        integer     check (total_deaths_ytd   >= 0),
    dhaka_city_cases_24h    integer     check (dhaka_city_cases_24h    >= 0),
    outside_dhaka_cases_24h integer     check (outside_dhaka_cases_24h >= 0),
    created_at              timestamptz not null default now()
);

comment on table public.daily_summaries is 'National DGHS dengue figures, one row per reporting day. A null column means DGHS did not publish that figure, never that the figure was zero.';

-- ---------------------------------------------------------------------------
-- regional_breakdowns — per-district figures for a reporting day
-- ---------------------------------------------------------------------------
create table if not exists public.regional_breakdowns (
    id            uuid primary key default gen_random_uuid(),
    report_date   date        not null
                  references public.daily_summaries (report_date)
                  on delete cascade,
    division_name varchar(64),
    district_name varchar(64) not null,
    cases_24h     integer     not null default 0 check (cases_24h  >= 0),
    deaths_24h    integer     not null default 0 check (deaths_24h >= 0),
    created_at    timestamptz not null default now(),
    -- Lets the scraper upsert a day repeatedly without duplicating districts.
    unique (report_date, district_name)
);

comment on table public.regional_breakdowns is 'Per-district figures. DGHS reports Dhaka city corporations separately from Dhaka district; they are kept as distinct district_name values so they are never summed twice.';

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
-- Descending: every read is "most recent first".
create index if not exists idx_daily_summaries_report_date
    on public.daily_summaries (report_date desc);

create index if not exists idx_regional_report_date
    on public.regional_breakdowns (report_date desc);

create index if not exists idx_regional_district
    on public.regional_breakdowns (district_name);

create index if not exists idx_regional_division
    on public.regional_breakdowns (division_name);

-- Serves /districts/{name}, which filters by district and orders by date.
create index if not exists idx_regional_district_date
    on public.regional_breakdowns (district_name, report_date desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
-- These are aggregate public-health figures with no personal data, so reads
-- are open. Writes are closed to everyone: the ingestion job uses the
-- service-role key, which bypasses RLS, so no policy should grant INSERT or
-- UPDATE to anon. A leaked anon key must not be able to falsify case counts.
alter table public.daily_summaries     enable row level security;
alter table public.regional_breakdowns enable row level security;

drop policy if exists "daily_summaries are publicly readable" on public.daily_summaries;
create policy "daily_summaries are publicly readable"
    on public.daily_summaries
    for select
    to anon, authenticated
    using (true);

drop policy if exists "regional_breakdowns are publicly readable" on public.regional_breakdowns;
create policy "regional_breakdowns are publicly readable"
    on public.regional_breakdowns
    for select
    to anon, authenticated
    using (true);

-- ---------------------------------------------------------------------------
-- latest_summary — the newest day, for the /latest endpoint
-- ---------------------------------------------------------------------------
create or replace view public.latest_summary as
    select *
    from public.daily_summaries
    order by report_date desc
    limit 1;
