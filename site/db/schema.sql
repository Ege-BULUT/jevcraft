-- JevCraft tables, prefixed jc_ (the database is shared with Jev Play Games). Idempotent.

-- One row per decision Jev made in the game: what it saw, the options, what it picked.
create table if not exists jc_decisions (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  state      text not null,
  options    jsonb not null,   -- [{id, label, detail}]
  probs      jsonb not null,   -- option id -> probability
  action     text not null,
  confidence real,
  latency_ms integer not null,
  tokens     integer not null,
  snapshot   jsonb             -- health, hunger, pos, inventory ... as the mod reported them
);
create index if not exists jc_decisions_at on jc_decisions (at desc);

create table if not exists jc_spend (
  day          date primary key,
  input_tokens bigint not null default 0
);

alter table jc_decisions enable row level security;
alter table jc_spend enable row level security;
drop policy if exists "public read" on jc_decisions;
create policy "public read" on jc_decisions for select using (true);

do $$ begin
  alter publication supabase_realtime add table jc_decisions;
exception when duplicate_object then null; end $$;

create or replace function jc_add_spend(p_tokens integer) returns bigint language sql as $$
  insert into jc_spend (day, input_tokens) values ((now() at time zone 'utc')::date, p_tokens)
  on conflict (day) do update set input_tokens = jc_spend.input_tokens + excluded.input_tokens
  returning input_tokens;
$$;
revoke execute on function jc_add_spend(integer) from public, anon, authenticated;

-- Live chat. Rows are written only by /api/chat (service role); visitors read name and body only.
create table if not exists jc_chat (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  name    text not null check (char_length(name) between 1 and 24),
  body    text not null check (char_length(body) between 1 and 280),
  ip_hash text not null   -- salted hash of the sender's IP, for rate limits; never readable by visitors
);
create index if not exists jc_chat_at on jc_chat (at desc);
create index if not exists jc_chat_ip_at on jc_chat (ip_hash, at desc);
alter table jc_chat enable row level security;
drop policy if exists "public read" on jc_chat;
create policy "public read" on jc_chat for select using (true);
-- RLS cannot hide a column, column privileges can: visitors may select everything but ip_hash.
revoke select on jc_chat from anon, authenticated;
grant select (id, at, name, body) on jc_chat to anon, authenticated;
do $$ begin
  alter publication supabase_realtime add table jc_chat (id, at, name, body);
exception when duplicate_object then null; end $$;

-- Two-hourly status reports, written by the poster on the game machine through /api/report.
create table if not exists jc_reports (
  id       bigserial primary key,
  at       timestamptz not null default now(),
  data     jsonb not null,   -- window, stats, advancements, moments, biggest moment
  tweet_id text
);
alter table jc_reports enable row level security;
drop policy if exists "public read" on jc_reports;
create policy "public read" on jc_reports for select using (true);

-- Running totals for the whole run, pushed by the poster every minute (one row, id 1).
create table if not exists jc_stats (
  id   integer primary key default 1 check (id = 1),
  at   timestamptz not null default now(),
  data jsonb not null
);
alter table jc_stats enable row level security;
drop policy if exists "public read" on jc_stats;
create policy "public read" on jc_stats for select using (true);
do $$ begin
  alter publication supabase_realtime add table jc_stats;
exception when duplicate_object then null; end $$;
