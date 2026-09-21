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
