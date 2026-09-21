// Every two hours: a status report of what Jev did in the game, stored on the site and posted on X
// with a link to it.
//
//   node agent/x-poster.mjs            drafts only: appends to run/x-drafts.txt, posts nothing
//   X_LIVE=1 node agent/x-poster.mjs   stores the report on the site and shares it (see share())
//   node agent/x-poster.mjs preview    prints the report for the last two hours of the log so far
//   node agent/x-poster.mjs whoami     checks the X credentials
//
// Everything in a report is counted from the game log (digs, placements, deaths and their cause,
// kills, crafted items, advancements, positions) and from the time of day in Jev's decisions, so a
// post states only what happened. Keys come from the macOS keychain.
import { createHmac, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, appendFileSync, statSync, openSync, readSync, closeSync } from 'node:fs';

const ROOT = new URL('..', import.meta.url).pathname;
const LOG = `${ROOT}run/luanti.log`;
const STATE = `${ROOT}run/x-state.json`;
const EVENTS = `${ROOT}run/x-events.jsonl`;
const DRAFTS = `${ROOT}run/x-drafts.txt`;
const SITE = 'https://jevcraft.vercel.app';
const LIVE = process.env.X_LIVE === '1';
const WINDOW = 2 * 3_600_000;
const TZ = 'Europe/Istanbul'; // shown as GMT+3
// Two or three tags help discovery; more reads as spam. Not #Minecraft: this game is not Minecraft.
const TAGS = '#AI #AIagents #VoxeLibre';

const MILESTONES = {
  gather_wood: 'chopped its first logs', craft_crafting_table: 'built its first crafting table',
  craft_wooden_tools: 'made wooden tools', craft_stone_tools: 'upgraded to stone tools', craft_furnace: 'built a furnace',
  craft_iron_tools: 'forged iron tools', build_shelter: 'built its first shelter', hunt_food: 'hunted its first meal',
  fight_hostile: 'won its first fight', craft_bed: 'crafted a bed', sleep: 'slept through a night', farm: 'planted a farm',
  trade_with_villager: 'traded with a villager', build_nether_portal: 'built a Nether portal',
};
const CRAFTED = /(planks|stick|pickaxe|axe|sword|shovel|hoe|crafting table|furnace|torch|bed|bread|chest|door|helmet|chestplate|leggings|boots|bucket|ladder|boat|shield|bow|arrow)$/;
const GAINS = /^(raw iron|iron ore|raw gold|gold ore|diamond|coal|emerald|lapis lazuli|redstone|obsidian)$/;
const ORES = { coal: 'dug up its first coal', iron: 'found iron ore', gold: 'found gold', diamond: 'found DIAMONDS', emerald: 'found an emerald' };
// Rank for "biggest moment": rarer and later-game first.
const WEIGHT = { 'found DIAMONDS': 100, 'built a Nether portal': 95, 'traded with a villager': 60, 'forged iron tools': 50,
  'found an emerald': 45, 'found gold': 40, 'slept through a night': 35, 'crafted a bed': 30, 'found iron ore': 25 };

const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8'))
  : { offset: Number(process.env.X_FROM_OFFSET ?? 0), seen: [], start: null, lastReport: null };
const save = () => writeFileSync(STATE, JSON.stringify(state, null, 1));

function readNewLines() {
  const size = statSync(LOG).size;
  if (size < state.offset) state.offset = 0;
  const fd = openSync(LOG, 'r');
  const buf = Buffer.alloc(size - state.offset);
  readSync(fd, buf, 0, buf.length, state.offset);
  closeSync(fd);
  const text = buf.toString('utf8');
  const end = text.lastIndexOf('\n') + 1; // a half-written last line waits for the next read
  state.offset += Buffer.byteLength(text.slice(0, end));
  return text.slice(0, end).split('\n').filter(Boolean);
}

// One compact event per interesting log line; appended to run/x-events.jsonl.
function parse(lines) {
  const out = [];
  for (const line of lines) {
    const m = /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}): (.*)$/.exec(line);
    if (!m) continue;
    const at = new Date(`${m[1].replace(' ', 'T')}+03:00`).toISOString(); // the game machine logs GMT+3
    const b = m[2];
    state.start ??= at;
    const pos = /\((-?\d+),(-?\d+),(-?\d+)\)/.exec(b);
    const p = pos && pos.slice(1).map(Number);
    let d;
    if ((d = /CHAT: Jev (was slain by .+|was shot by .+|was killed by .+|drowned.*|fell .+|burned.*|was blown up.*|suffocated.*|starved.*|tried to swim in lava.*|died.*)$/.exec(b))) {
      out.push({ at, k: 'death', v: d[1].replace(/\.$/, '').replace(/^was /, '') });
    } else if ((d = /CHAT: Jev has made the advancement \[(.+)\]/.exec(b))) {
      out.push({ at, k: 'adv', v: d[1] });
    } else if (/: Jev digs /.test(b)) {
      out.push({ at, k: 'dig', p });
    } else if (/: Jev places node /.test(b)) {
      out.push({ at, k: 'place', p });
    } else if (/\[jev_agent\] respawned at/.test(b)) {
      out.push({ at, k: 'respawn', p });
    } else if ((d = /\[jev_agent\] skill (\w+) succeeded: (.*)$/.exec(b))) {
      const [, skill, msg] = d;
      // Count only the inventory delta in [brackets]: the message text often repeats it ("+3 raw
      // iron ... [+3 raw iron]"), and picking items back up after a death is no new gain.
      const delta = /\[([^\]]*)\]\s*$/.exec(msg)?.[1] ?? '';
      if (skill !== 'recover_items') for (const [, n, item] of `${delta},`.matchAll(/\+(\d+) ([a-z][a-z ]*?)(?=,)/g)) if (GAINS.test(item)) out.push({ at, k: 'gain', v: item.trim(), n: Number(n) });
      const kill = /killed ([a-z ]+?)(?: \[|$)/.exec(msg);
      if (kill) out.push({ at, k: 'kill', v: kill[1].trim() });
      if (skill.startsWith('craft_')) {
        // Craft skills also pick up whatever they dig on the way; count only made things.
        for (const [, n, item] of `${delta},`.matchAll(/\+(\d+) ([a-z][a-z ]*?)(?=,)/g)) if (CRAFTED.test(item)) out.push({ at, k: 'craft', v: item.trim(), n: Number(n) });
      }
      if (MILESTONES[skill] && !state.seen.includes(skill)) { state.seen.push(skill); out.push({ at, k: 'milestone', v: MILESTONES[skill] }); }
      if (skill === 'mine_ores') for (const [ore, text] of Object.entries(ORES)) {
        if (msg.includes(ore) && !state.seen.includes(`ore:${ore}`)) { state.seen.push(`ore:${ore}`); out.push({ at, k: 'milestone', v: text }); }
      }
      if (p) out.push({ at, k: 'pos', p });
    }
  }
  return out;
}

const loadEvents = () => existsSync(EVENTS) ? readFileSync(EVENTS, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];
const clock = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: TZ });
const tally = (list) => list.reduce((m, v) => ({ ...m, [v]: (m[v] ?? 0) + 1 }), {});
const top = (obj, n) => Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, n);

// In-game days from the time of day in Jev's decisions: each wrap past midnight starts a new day.
async function gameDays(to) {
  const env = readFileSync(`${ROOT}site/.env.local`, 'utf8');
  const get = (k) => new RegExp(`^${k}="?([^"\\n]+)`, 'm').exec(env)?.[1];
  const url = `${get('NEXT_PUBLIC_SUPABASE_URL')}/rest/v1/jc_decisions?select=snapshot&at=gte.${state.start}&at=lt.${to}&order=at`;
  const r = await fetch(url, { headers: { apikey: get('NEXT_PUBLIC_SUPABASE_ANON_KEY') } }).catch(() => null);
  const rows = r?.ok ? await r.json() : [];
  let days = 1, prev = null;
  for (const { snapshot } of rows) {
    const t = snapshot?.time_of_day;
    if (typeof t === 'number') { if (prev !== null && t < prev - 0.5) days++; prev = t; }
  }
  return days;
}

async function buildReport(from, to) {
  const ev = loadEvents().filter((e) => e.at >= from && e.at < to);
  const of = (k) => ev.filter((e) => e.k === k);
  // Distance: straight lines between consecutive known positions, skipping respawn teleports.
  let dist = 0, last = null;
  for (const e of ev) {
    if (!e.p) continue;
    if (e.k === 'respawn') { last = e.p; continue; }
    if (last) { const d = Math.hypot(e.p[0] - last[0], e.p[1] - last[1], e.p[2] - last[2]); if (d < 80) dist += d; }
    last = e.p;
  }
  const crafts = of('craft').reduce((m, e) => ({ ...m, [e.v]: (m[e.v] ?? 0) + e.n }), {});
  const moments = [...of('milestone'), ...of('death').map((e) => ({ ...e, v: `died: ${e.v}` })), ...of('adv').map((e) => ({ ...e, v: `advancement “${e.v}”` }))]
    .sort((a, b) => a.at.localeCompare(b.at)).map((e) => ({ at: e.at, text: e.v }));
  const ranked = of('milestone').sort((a, b) => (WEIGHT[b.v] ?? 10) - (WEIGHT[a.v] ?? 10));
  const hour = (iso) => Math.floor((Date.parse(iso) - Date.parse(state.start)) / 3_600_000);
  return {
    from, to, hours: [hour(from) + 1, Math.max(hour(from) + 1, hour(to))], day: await gameDays(to),
    stats: {
      deaths: of('death').length, causes: tally(of('death').map((e) => e.v)), distance_m: Math.round(dist),
      dug: of('dig').length, placed: of('place').length, crafts, crafted: Object.values(crafts).reduce((a, b) => a + b, 0),
      kills: tally(of('kill').map((e) => e.v)),
    },
    advancements: of('adv').map((e) => e.v),
    moments,
    biggest: ranked[0] ? { at: ranked[0].at, text: ranked[0].v } : moments[0] ?? null,
  };
}

const tweetLength = (s) => s.replace(/https?:\/\/\S+/g, 'x'.repeat(23)).length; // X counts a link as 23

// The post: the numbers first, then advancements and the biggest moment while they fit in 280.
function tweet(r, link) {
  const s = r.stats, kills = Object.values(s.kills).reduce((a, b) => a + b, 0);
  const short = (c) => c.replace(/^(slain|shot|killed|blown up) by /, '').replace('tried to swim in lava', 'lava');
  const causes = top(s.causes, 2).map(([c, n]) => (n > 1 ? `${short(c)} ×${n}` : short(c))).join(', ');
  const hours = r.hours[0] === r.hours[1] ? `Hour ${r.hours[0]}` : `Hours ${r.hours[0]}–${r.hours[1]}`;
  const head = [
    '🧱 JevCraft · Jev lives within block world', // the account posts every Jev experiment, so name this one
    `${hours} · in-game day ${r.day}`,
    '',
    `⛏ ${s.dug.toLocaleString('en')} dug · 🧱 ${s.placed} placed · 🛠 ${s.crafted} crafted`,
    `⚔ ${kills} kill${kills === 1 ? '' : 's'} · ☠ ${s.deaths} death${s.deaths === 1 ? '' : 's'}${s.deaths ? ` (${causes})` : ''}`,
    `🧭 ~${s.distance_m >= 1000 ? `${(s.distance_m / 1000).toFixed(1)} km` : `${s.distance_m} m`} travelled`,
  ];
  const extras = []; // dropped from the end when the post runs long, so the biggest moment stays
  if (r.biggest) extras.push(`⭐ ${r.biggest.text}, ${clock(r.biggest.at)} GMT+3`);
  if (r.advancements.length) extras.push(`🏆 ${r.advancements.slice(0, 3).join(', ')}${r.advancements.length > 3 ? ` +${r.advancements.length - 3}` : ''}`);
  const foot = ['', `Full report ▶ ${link}`, TAGS]; // tags come before the optional extras
  for (let n = extras.length; n >= 0; n--) {
    const text = [...head, ...extras.slice(0, n), ...foot].join('\n');
    if (tweetLength(text) <= 280) return text;
  }
  return [...head, ...foot].join('\n');
}

// OAuth 1.0a request signing, as the X API requires for posting on behalf of the account.
const key = (s) => execFileSync('security', ['find-generic-password', '-a', 'jevcraft', '-s', s, '-w'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
const enc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
async function x(method, url, body) {
  const [ck, cs, tk, ts] = ['x-api-key', 'x-api-secret', 'x-access-token', 'x-access-secret'].map(key);
  const oauth = { oauth_consumer_key: ck, oauth_nonce: randomBytes(16).toString('hex'), oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: String(Math.floor(Date.now() / 1000)), oauth_token: tk, oauth_version: '1.0' };
  const params = Object.entries(oauth).map(([k, v]) => `${enc(k)}=${enc(v)}`).sort().join('&');
  oauth.oauth_signature = createHmac('sha1', `${enc(cs)}&${enc(ts)}`).update([method, enc(url), enc(params)].join('&')).digest('base64');
  const header = 'OAuth ' + Object.entries(oauth).map(([k, v]) => `${enc(k)}="${enc(v)}"`).join(', ');
  const r = await fetch(url, { method, headers: { authorization: header, 'content-type': 'application/json' }, body: body && JSON.stringify(body) });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

const site = (method, body) => fetch(`${SITE}/api/report`, {
  method, headers: { 'x-jevcraft-key': key('jevcraft-key'), 'content-type': 'application/json' }, body: JSON.stringify(body),
}).then((r) => r.json());

// Sharing without paid API credits. X: a notification that opens the post prefilled (one click
// on Post; X_MODE=api posts through the paid API instead). Bluesky and Mastodon: posted directly,
// when their tokens are in the keychain.
const has = (s) => { try { key(s); return true; } catch { return false; } };

function hashtagFacets(text) {
  const out = [];
  for (const m of text.matchAll(/(^|\s)#([A-Za-z][\w]*)/g)) {
    const byteStart = Buffer.byteLength(text.slice(0, m.index + m[1].length));
    out.push({ index: { byteStart, byteEnd: byteStart + Buffer.byteLength(`#${m[2]}`) }, features: [{ $type: 'app.bsky.richtext.facet#tag', tag: m[2] }] });
  }
  return out;
}

async function share(p) {
  const run = async (channel, fn) => {
    if (p.done[channel] !== false) return;
    try { await fn(); p.done[channel] = true; console.log(`[share] report ${p.id} on ${channel}`); }
    catch (e) { console.log(`[share] ${channel} failed: ${e.message}`); }
  };
  await run('x', async () => {
    if (process.env.X_MODE === 'api') {
      const r = await x('POST', 'https://api.x.com/2/tweets', { text: p.text });
      if (r.status !== 201) throw new Error(`${r.status} ${JSON.stringify(r.json).slice(0, 160)}`);
      await site('PATCH', { id: p.id, tweet_id: r.json.data.id });
      return;
    }
    const intent = `https://x.com/intent/post?text=${encodeURIComponent(p.text)}`;
    appendFileSync(`${ROOT}run/x-intents.txt`, `${new Date().toISOString()} report ${p.id}\n${intent}\n`);
    execFileSync('terminal-notifier', ['-title', 'JevCraft', '-subtitle', 'Status update ready', '-message', 'Click to post it on X',
      '-open', intent, '-sound', 'Glass', '-group', `jevcraft-${p.id}`]);
  });
  await run('bsky', async () => {
    const pds = 'https://bsky.social/xrpc';
    const post = (path, body, headers = {}) => fetch(`${pds}/${path}`, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) })
      .then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(`${path} ${r.status} ${JSON.stringify(j).slice(0, 120)}`); return j; });
    const session = await post('com.atproto.server.createSession', { identifier: key('bsky-handle'), password: key('bsky-app-password') });
    const auth = { authorization: `Bearer ${session.accessJwt}` };
    const card = await fetch(`${SITE}/api/og?report=${p.id}`).then((r) => r.arrayBuffer());
    const thumb = await fetch(`${pds}/com.atproto.repo.uploadBlob`, { method: 'POST', headers: { ...auth, 'content-type': 'image/png' }, body: Buffer.from(card) }).then((r) => r.json());
    const text = p.text, start = Buffer.from(text).indexOf(Buffer.from(p.link)); // facets count UTF-8 bytes
    await post('com.atproto.repo.createRecord', { repo: session.did, collection: 'app.bsky.feed.post', record: {
      $type: 'app.bsky.feed.post', text, createdAt: new Date().toISOString(),
      facets: [
        ...(start < 0 ? [] : [{ index: { byteStart: start, byteEnd: start + Buffer.byteLength(p.link) }, features: [{ $type: 'app.bsky.richtext.facet#link', uri: p.link }] }]),
        ...hashtagFacets(text), // Bluesky only makes a #tag clickable when it is marked up
      ],
      embed: { $type: 'app.bsky.embed.external', external: { uri: p.link, title: 'JevCraft status update', description: 'What Jev did in the block world in the last two hours.', thumb: thumb.blob } },
    } }, auth);
  });
  await run('mastodon', async () => {
    const r = await fetch(`https://${key('mastodon-instance')}/api/v1/statuses`, { method: 'POST',
      headers: { authorization: `Bearer ${key('mastodon-token')}`, 'content-type': 'application/json' }, body: JSON.stringify({ status: p.text }) });
    if (!r.ok) throw new Error(`${r.status} ${(await r.text()).slice(0, 120)}`);
  });
  save();
}

// Running totals for the whole run, for the stats strip and cards on the site.
async function dayCount() {
  const env = readFileSync(`${ROOT}site/.env.local`, 'utf8');
  const get = (k) => new RegExp(`^${k}="?([^"\\n]+)`, 'm').exec(env)?.[1];
  const since = state.todAt ?? state.start;
  const url = `${get('NEXT_PUBLIC_SUPABASE_URL')}/rest/v1/jc_decisions?select=at,snapshot&at=gt.${since}&order=at&limit=2000`;
  const rows = await fetch(url, { headers: { apikey: get('NEXT_PUBLIC_SUPABASE_ANON_KEY') } }).then((r) => (r.ok ? r.json() : [])).catch(() => []);
  state.days ??= 1;
  for (const { at, snapshot } of rows) {
    const t = snapshot?.time_of_day;
    if (typeof t === 'number') { if (state.tod != null && t < state.tod - 0.5) state.days++; state.tod = t; }
    state.todAt = at;
  }
  return state.days;
}

async function pushStats() {
  const ev = loadEvents();
  const tallyBy = (k, f = (e) => e.v) => ev.filter((e) => e.k === k).reduce((m, e) => ({ ...m, [f(e)]: (m[f(e)] ?? 0) + (e.n ?? 1) }), {});
  let dist = 0, last = null;
  for (const e of ev) {
    if (!e.p) continue;
    if (e.k === 'respawn') { last = e.p; continue; }
    if (last) { const d = Math.hypot(e.p[0] - last[0], e.p[1] - last[1], e.p[2] - last[2]); if (d < 80) dist += d; }
    last = e.p;
  }
  const deaths = ev.filter((e) => e.k === 'death').map((e) => Date.parse(e.at));
  const marks = [Date.parse(state.start), ...deaths, Date.now()];
  const longest = Math.max(...marks.slice(1).map((t, i) => t - marks[i]));
  const data = {
    updated: new Date().toISOString(), start: state.start, day: await dayCount(),
    totals: {
      dug: ev.filter((e) => e.k === 'dig').length, placed: ev.filter((e) => e.k === 'place').length,
      crafted: ev.filter((e) => e.k === 'craft').reduce((a, e) => a + e.n, 0), distance_blocks: Math.round(dist),
      longest_life_s: Math.round(longest / 1000), kills: tallyBy('kill'), deaths: tallyBy('death'), gains: tallyBy('gain'),
    },
    advancements: ev.filter((e) => e.k === 'adv').map((e) => ({ name: e.v, at: e.at })),
  };
  const r = await fetch(`${SITE}/api/stats`, { method: 'POST', headers: { 'x-jevcraft-key': key('jevcraft-key'), 'content-type': 'application/json' }, body: JSON.stringify({ data }) });
  if (!r.ok) console.log(`[stats] push failed ${r.status}`);
}

async function tick() {
  if (!existsSync(LOG)) return;
  const fresh = parse(readNewLines());
  if (fresh.length) appendFileSync(EVENTS, fresh.map((e) => JSON.stringify(e)).join('\n') + '\n');
  save();
  if (!state.start) return;
  if (LIVE) await pushStats().catch((e) => console.log(`[stats] ${e.message}`));
  if (state.pending) { // a stored report still to be shared; each channel is retried on its own
    if (Date.now() < (state.retryAt ?? 0)) return;
    await share(state.pending);
    const open = Object.entries(state.pending.done).filter(([, ok]) => !ok).map(([c]) => c);
    if (open.length && Date.now() - state.pending.at < 6 * 3_600_000) {
      state.retryAt = Date.now() + 15 * 60_000;
      save();
      throw new Error(`report ${state.pending.id}: ${open.join(', ')} not shared yet; retrying in 15 min`);
    }
    state.pending = null; state.retryAt = null;
    save();
    return;
  }
  const from = state.lastReport ?? state.start;
  const to = new Date(Date.parse(from) + WINDOW).toISOString();
  if (Date.now() < Date.parse(to) + 5 * 60_000) return; // wait until the window's recording is online
  const report = await buildReport(from, to);
  if (report.stats.dug + report.stats.placed + report.moments.length > 0) {
    if (LIVE) {
      const { id } = await site('POST', { data: report });
      if (!id) throw new Error('the site did not store the report');
      const channels = { x: false, ...(has('bsky-app-password') && { bsky: false }), ...(has('mastodon-token') && { mastodon: false }) };
      state.pending = { id, at: Date.now(), link: `${SITE}/?report=${id}`, text: tweet(report, `${SITE}/?report=${id}`), done: channels };
      state.lastReport = to;
      save();
      return tick();
    } else {
      appendFileSync(DRAFTS, `---- ${new Date().toISOString()}\n${tweet(report, `${SITE}/?report=N`)}\n`);
      console.log('[x] report drafted');
    }
  }
  state.lastReport = to; // a window with no play at all (machine asleep) is skipped, not posted
  save();
}

const cmd = process.argv[2];
if (cmd === 'rebuild') {
  const from = Number(process.env.X_FROM_OFFSET ?? 0);
  Object.assign(state, { offset: from, seen: [], start: null });
  const ev = parse(readNewLines());
  writeFileSync(EVENTS, ev.map((e) => JSON.stringify(e)).join('\n') + '\n');
  save();
  console.log(`rebuilt ${ev.length} events from offset ${from}`);
} else if (cmd === 'whoami') {
  const r = await x('GET', 'https://api.x.com/2/users/me');
  console.log(r.status, JSON.stringify(r.json));
} else if (cmd === 'preview') {
  const fresh = parse(readNewLines());
  appendFileSync(EVENTS, fresh.map((e) => JSON.stringify(e)).join('\n') + '\n');
  const to = new Date().toISOString(), from = new Date(Date.now() - WINDOW).toISOString();
  const r = await buildReport(from < state.start ? state.start : from, to);
  const text = tweet(r, `${SITE}/?report=N`);
  writeFileSync(`${ROOT}run/x-preview.json`, JSON.stringify(r));
  console.log(`${text}\n\n(${tweetLength(text)} chars); full report in run/x-preview.json`);
} else {
  for (;;) { await tick().catch((e) => console.log(`[x] ${e.message}`)); await new Promise((r) => setTimeout(r, 60_000)); }
}
