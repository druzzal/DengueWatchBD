-- Optional Supabase schema.
--
-- NOT REQUIRED to run this pipeline. The daily job publishes a static JSON
-- file, which the iOS app fetches with a conditional GET — that is already the
-- simplest architecture that meets the requirement, costs nothing to host, and
-- has no credentials to leak.
--
-- This schema exists for the case where you later want queryable history,
-- multiple consumers, or server-side filtering. It has NOT been applied or
-- tested against a live Supabase project, because provisioning one needs your
-- account. Treat it as a starting point, not as verified migration.

create table if not exists dengue_daily (
    id                    bigserial primary key,
    report_date           date        not null,
    cases_24h             integer     check (cases_24h >= 0),
    deaths_24h            integer     check (deaths_24h >= 0),
    total_cases           integer     check (total_cases >= 0),
    total_deaths          integer     check (total_deaths >= 0),
    current_hospitalised  integer     check (current_hospitalised >= 0),
    discharged            integer     check (discharged >= 0),
    source                text        not null default 'DGHS',
    source_url            text        not null,
    source_last_updated   date,
    ingested_at           timestamptz not null default now(),
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    unique (report_date)
);

-- geographic_level keeps district, division and city-corporation rows apart,
-- because DGHS reports Dhaka's two city corporations separately from Dhaka
-- district and conflating them double-counts.
create table if not exists dengue_geographic (
    id               bigserial primary key,
    report_date      date    not null,
    geographic_level text    not null
        check (geographic_level in ('division','district','city_corporation','other')),
    division         text,
    district         text,
    area_name        text    not null,
    cases            integer check (cases >= 0),
    deaths           integer check (deaths >= 0),
    source           text    not null default 'DGHS',
    source_url       text    not null,
    ingested_at      timestamptz not null default now(),
    unique (report_date, geographic_level, area_name)
);

create index if not exists dengue_geographic_date_idx
    on dengue_geographic (report_date desc);
create index if not exists dengue_daily_date_idx
    on dengue_daily (report_date desc);

-- Every attempt, successful or not. Without this there is no way to tell
-- "DGHS published nothing today" from "our parser broke".
create table if not exists dengue_data_runs (
    id                    bigserial primary key,
    run_started_at        timestamptz not null,
    run_completed_at      timestamptz,
    source_last_updated   date,
    status                text not null
        check (status in ('success','no_change','error')),
    days_fetched          integer default 0,
    days_parsed           integer default 0,
    days_skipped          integer default 0,
    records_written       integer default 0,
    validation_rejections integer default 0,
    validation_anomalies  integer default 0,
    error_message         text,
    created_at            timestamptz not null default now()
);
