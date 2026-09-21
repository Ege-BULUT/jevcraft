// Turns what happens in the game into posts on X, each linking to that moment of the recording.
//
//   node agent/x-poster.mjs            drafts only: appends to run/x-drafts.txt, posts nothing
//   X_LIVE=1 node agent/x-poster.mjs   posts for real
//
// Highlights come from the game log (death messages, the first success of each notable skill,
// the first of each ore), so every post states only what actually happened. At most one post per
// MIN_GAP; highlights in between are gathered into it. Keys are read from the macOS keychain.
import { createHmac, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, appendFileSync, statSync, openSync, readSync, closeSync } from 'node:fs';

const ROOT = new URL('..', import.meta.url).pathname;
const LOG = `${ROOT}run/luanti.log`;
const STATE = `${ROOT}run/x-state.json`;
const DRAFTS = `${ROOT}run/x-drafts.txt`;
const SITE = 'https://jevcraft.vercel.app';
const LIVE = process.env.X_LIVE === '1';
const MIN_GAP = 90 * 60_000;      // between posts
const DEATH_GAP = 45 * 60_000;    // a death may go out sooner
const TZ = 'Europe/Istanbul';

const FIRSTS = {
  gather_wood: 'chopped its first logs',
  craft_crafting_table: 'built its first crafting table',
  craft_wooden_tools: 'made wooden tools',
  craft_stone_tools: 'upgraded to stone tools',
  craft_furnace: 'built a furnace',
  craft_iron_tools: 'forged iron tools',
  build_shelter: 'built its first shelter',
  hunt_food: 'hunted its first meal',
  fight_hostile: 'won its first fight',
  craft_bed: 'crafted a bed',
  sleep: 'slept through its first night',
  farm: 'planted its first farm',
  trade_with_villager: 'traded with a villager',
  build_nether_portal: 'built a Nether portal',
};
const ORES = { coal: 'dug up its first coal', iron: 'found iron ore', gold: 'found gold', diamond: 'found DIAMONDS', emerald: 'found an emerald' };

const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8'))
  : { offset: Number(process.env.X_FROM_OFFSET ?? 0), seen: [], pending: [], lastPost: 0, deaths: 0, start: null };
const save = () => writeFileSync(STATE, JSON.stringify(state, null, 1));

// Log lines look like "2026-09-21 13:17:56: ACTION[Main]: CHAT: Jev was slain by Zombie".
function readNewLines() {
  const size = statSync(LOG).size;
  if (size < state.offset) state.offset = 0; // log rotated
  const fd = openSync(LOG, 'r');
  const buf = Buffer.alloc(size - state.offset);
  readSync(fd, buf, 0, buf.length, state.offset);
  closeSync(fd);
  const text = buf.toString('utf8');
  const end = text.lastIndexOf('\n') + 1; // keep a half-written last line for next time
  state.offset += Buffer.byteLength(text.slice(0, end));
  return text.slice(0, end).split('\n').filter(Boolean);
}

function highlights(lines) {
  const out = [];
  for (const line of lines) {
    const m = /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}): (.*)$/.exec(line);
    if (!m) continue;
    const at = new Date(`${m[1].replace(' ', 'T')}+03:00`).toISOString(); // the Mac's local time, Istanbul
    const body = m[2];
    state.start ??= at;
    let d;
    if ((d = /CHAT: Jev (was slain by .+|drowned.*|fell .+|died.*|burned.*|was blown up.*|suffocated.*|starved.*|was shot.*)$/.exec(body))) {
      state.deaths++;
      out.push({ at, kind: 'death', text: d[1].replace(/\.$/, '').replace(/^was /, ''), n: state.deaths });
    } else if ((d = /\[jev_agent\] skill (\w+) succeeded: (.*)$/.exec(body))) {
      const [, skill, msg] = d;
      if (FIRSTS[skill] && !state.seen.includes(skill)) { state.seen.push(skill); out.push({ at, kind: 'first', text: FIRSTS[skill] }); }
      if (skill === 'mine_ores') for (const [ore, text] of Object.entries(ORES)) {
        if (msg.includes(ore) && !state.seen.includes(`ore:${ore}`)) { state.seen.push(`ore:${ore}`); out.push({ at, kind: 'first', text }); }
      }
    }
  }
  return out;
}

const clock = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: TZ });
const hourOfRun = (iso) => Math.floor((Date.parse(iso) - Date.parse(state.start)) / 3_600_000) + 1;
const tweetLength = (s) => s.replace(/https?:\/\/\S+/g, 'x'.repeat(23)).length; // X counts every link as 23

// A post lists the milestones one per line; deaths in the same post are summed up in one line.
function compose(events) {
  const lead = events[0];
  const link = `${SITE}/?t=${lead.at}`;
  const head = `Hour ${hourOfRun(lead.at)} of Jev playing a block world, live and unattended:`;
  const tail = `\n\n▶ Watch from ${clock(lead.at)} (Istanbul): ${link}\n#AI #VoxeLibre`;
  const render = (list) => {
    const deaths = list.filter((e) => e.kind === 'death');
    const causes = Object.entries(deaths.reduce((m, e) => ({ ...m, [e.text]: (m[e.text] ?? 0) + 1 }), {}))
      .sort((a, b) => b[1] - a[1]).map(([c, n]) => (n > 1 ? `${n}× ${c}` : c)).join(', ');
    const lines = list.filter((e) => e.kind !== 'death').map((e) => [e.at, `• ${clock(e.at)} ${e.text}`]);
    if (deaths.length === 1) lines.push([deaths[0].at, `• ${clock(deaths[0].at)} died: ${causes}`]);
    if (deaths.length > 1) lines.push([deaths[0].at, `• ${clock(deaths[0].at)}–${clock(deaths.at(-1).at)} died ${deaths.length}×: ${causes}`]);
    return `${head}\n${lines.sort((a, b) => a[0].localeCompare(b[0])).map((l) => l[1]).join('\n')}${tail}`;
  };
  let used = 1;
  while (used < events.length && tweetLength(render(events.slice(0, used + 1))) <= 280) used++;
  return { text: render(events.slice(0, used)), used };
}

// OAuth 1.0a request signing, as the X API requires for posting on behalf of the account.
const key = (s) => execFileSync('security', ['find-generic-password', '-a', 'jevcraft', '-s', s, '-w']).toString().trim();
const enc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
async function x(method, url, body) {
  const [ck, cs, tk, ts] = ['x-api-key', 'x-api-secret', 'x-access-token', 'x-access-secret'].map(key);
  const oauth = { oauth_consumer_key: ck, oauth_nonce: randomBytes(16).toString('hex'), oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: String(Math.floor(Date.now() / 1000)), oauth_token: tk, oauth_version: '1.0' };
  const params = Object.entries(oauth).map(([k, v]) => `${enc(k)}=${enc(v)}`).sort().join('&');
  const base = [method, enc(url), enc(params)].join('&');
  oauth.oauth_signature = createHmac('sha1', `${enc(cs)}&${enc(ts)}`).update(base).digest('base64');
  const header = 'OAuth ' + Object.entries(oauth).map(([k, v]) => `${enc(k)}="${enc(v)}"`).join(', ');
  const r = await fetch(url, { method, headers: { authorization: header, 'content-type': 'application/json' }, body: body && JSON.stringify(body) });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

async function tick() {
  if (!existsSync(LOG)) return;
  state.pending.push(...highlights(readNewLines()));
  const now = Date.now();
  const hasDeath = state.pending.some((e) => e.kind === 'death');
  // Wait until the recording of the first pending moment is online (segments land ~3 min later).
  const ready = state.pending.length && now - Date.parse(state.pending[0].at) > 5 * 60_000;
  if (ready && now - state.lastPost > (hasDeath ? DEATH_GAP : MIN_GAP)) {
    const { text, used } = compose(state.pending);
    if (LIVE) {
      const r = await x('POST', 'https://api.x.com/2/tweets', { text });
      if (r.status !== 201) { console.log(`[x] post failed ${r.status} ${JSON.stringify(r.json).slice(0, 300)}`); save(); return; }
      console.log(`[x] posted ${r.json.data?.id}: ${text.split('\n')[1]}`);
    } else {
      appendFileSync(DRAFTS, `---- ${new Date().toISOString()}\n${text}\n`);
      console.log(`[x] draft written (${tweetLength(text)} chars)`);
    }
    state.pending = state.pending.slice(used);
    state.lastPost = now;
  }
  save();
}

if (process.argv[2] === 'preview') {
  // Drafts from the log so far, as if every gap had passed; posts and saves nothing.
  const events = highlights(readNewLines());
  while (events.length) { const { text, used } = compose(events); console.log(`---- ${tweetLength(text)} chars\n${text}\n`); events.splice(0, Math.max(1, used)); }
} else if (process.argv[2] === 'whoami') {
  const r = await x('GET', 'https://api.x.com/2/users/me');
  console.log(r.status, JSON.stringify(r.json));
} else {
  for (;;) { await tick().catch((e) => console.log(`[x] ${e.message}`)); await new Promise((r) => setTimeout(r, 60_000)); }
}
