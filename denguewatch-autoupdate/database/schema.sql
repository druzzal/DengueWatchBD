-- DengueWatch — Supabase schema
--
-- Apply in the Supabase SQL editor, or:
--   psql "$SUPABASE_DB_URL" -f database/schema.sql
-- Safe to re-run.

create table if not exists public.dengue_stats (
    report_date             date        primary key,
    total_cases_24h         integer     not null check (total_cases_24h  >= 0),
    total_deaths_24h        integer     not null check (total_deaths_24h >= 0),
    -- Nullable, not defaulted to 0. DGHS does not always publish the Dhaka
    -- split, and storing 0 for "not reported" would read as "no cases in
    -- Dhaka today" — a claim the source never made. NULL says "unknown".
    dhaka_cases_24h         integer     check (dhaka_cases_24h         >= 0),
    outside_dhaka_cases_24h integer     check (outside_dhaka_cases_24h >= 0),
    created_at              timestamptz not null default now()
);

comment on table public.dengue_stats is 'Daily national DGHS dengue figures, one row per reporting day. A null column means DGHS did not publish that figure, never that it was zero.';

-- Every read is "most recent first", which is what the app asks for.
create index if not exists idx_dengue_stats_report_date
    on public.dengue_stats (report_date desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
-- The iOS app ships the anon key, so treat it as public. These are aggregate
-- public-health figures with no personal data, so reading is open. No policy
-- grants insert, update or delete to anon: the scraper writes with the
-- service key, which bypasses RLS. A leaked anon key must not be able to
-- falsify case counts.
alter table public.dengue_stats enable row level security;

drop policy if exists "dengue_stats are publicly readable" on public.dengue_stats;
create policy "dengue_stats are publicly readable"
    on public.dengue_stats
    for select
    to anon, authenticated
    using (true);
