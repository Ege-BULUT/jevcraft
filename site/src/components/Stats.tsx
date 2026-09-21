'use client';
import { useEffect, useRef, useState, type CSSProperties, type PointerEvent } from 'react';
import { Press_Start_2P } from 'next/font/google';
import { browserDb } from '@/lib/db';
import { advancementTier, statTier, tierRank, type Tier } from '@/lib/tiers';
import { PixelIcon, type IconName } from './PixelIcon';
import { attachGodRays } from '@/lib/godrays';

const pixel = Press_Start_2P({ weight: '400', subsets: ['latin'] });

type StatsData = {
  updated: string; start: string; day: number;
  totals: { dug: number; placed: number; crafted: number; distance_blocks: number; longest_life_s: number;
    kills: Record<string, number>; deaths: Record<string, number>; gains: Record<string, number> };
  advancements: { name: string; at: string }[];
};

const TIER_NAME: Record<Tier, string> = { F: 'Wood', E: 'Stone', D: 'Iron', C: 'Emerald', B: 'Gold', A: 'Diamond', S: 'Obsidian', SS: 'Prismatic', SSS: 'Majestic' };
const sum = (o: Record<string, number>) => Object.values(o).reduce((a, b) => a + b, 0);
const n = (v: number) => v.toLocaleString('en');
const when = (iso: string) => new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Istanbul' });
const top = (o: Record<string, number>, k = 2) => Object.entries(o).sort((a, b) => b[1] - a[1]).slice(0, k).map(([c, v]) => `${c} ×${v}`).join(', ');

type Card = { key: string; title: string; kind: string; icon: IconName; tier: Tier; value: string; lines: string[]; foot: string };

function cards(d: StatsData): Card[] {
  const t = d.totals, km = t.distance_blocks / 1000, kills = sum(t.kills), deaths = sum(t.deaths);
  const diamond = t.gains['diamond'] ?? 0, iron = (t.gains['raw iron'] ?? 0) + (t.gains['iron ore'] ?? 0), coal = t.gains['coal'] ?? 0;
  const life = Math.round(t.longest_life_s / 60);
  const stats: Card[] = [
    { key: 'dug', title: 'Excavator', kind: 'Stat · Mining', icon: 'pickaxe', tier: statTier('dug', t.dug), value: `${n(t.dug)} blocks`, lines: ['dug out of the world'], foot: '' },
    { key: 'placed', title: 'Builder', kind: 'Stat · Building', icon: 'block', tier: statTier('placed', t.placed), value: `${n(t.placed)} blocks`, lines: ['placed by hand'], foot: '' },
    { key: 'crafted', title: 'Artisan', kind: 'Stat · Crafting', icon: 'hammer', tier: statTier('crafted', t.crafted), value: `${n(t.crafted)} items`, lines: ['tools, planks, stations'], foot: '' },
    { key: 'kills', title: 'Hunter', kind: 'Stat · Combat', icon: 'sword', tier: statTier('kills', kills), value: `${n(kills)} mobs`, lines: [top(t.kills) || 'no kills yet'], foot: '' },
    { key: 'deaths', title: 'Respawner', kind: 'Stat · Deaths', icon: 'skull', tier: statTier('deaths', deaths), value: `${n(deaths)} deaths`, lines: [top(t.deaths) || 'unbeaten so far'], foot: '' },
    { key: 'distance', title: 'Wanderer', kind: 'Stat · Travel', icon: 'compass', tier: statTier('km', km), value: `${n(t.distance_blocks)} blocks`, lines: [`≈ ${km.toFixed(2)} km on foot`], foot: '' },
    { key: 'days', title: 'Survivor', kind: 'Stat · Time', icon: 'sun', tier: statTier('days', d.day), value: `Day ${d.day}`, lines: ['in-game days lived through'], foot: '' },
    { key: 'life', title: 'Iron Will', kind: 'Stat · Survival', icon: 'heart', tier: statTier('life_min', life), value: `${life} min`, lines: ['longest life without dying'], foot: '' },
    { key: 'diamond', title: 'Diamond Hands', kind: 'Stat · Treasure', icon: 'diamond', tier: statTier('diamond', diamond), value: `${n(diamond)} diamonds`, lines: ['mined from the deep'], foot: '' },
    { key: 'iron', title: 'Ironmonger', kind: 'Stat · Ore', icon: 'iron', tier: statTier('iron', iron), value: `${n(iron)} iron`, lines: ['raw iron dug up'], foot: '' },
    { key: 'coal', title: 'Coal Miner', kind: 'Stat · Ore', icon: 'coal', tier: statTier('coal', coal), value: `${n(coal)} coal`, lines: ['fuel and torches'], foot: '' },
  ];
  const adv: Card[] = d.advancements.map((a): Card => ({
    key: `adv:${a.name}`, title: a.name, kind: 'Advancement', icon: 'trophy', tier: advancementTier(a.name),
    value: 'Unlocked', lines: [`${TIER_NAME[advancementTier(a.name)]} tier`], foot: when(a.at),
  })).sort((a, b) => tierRank(b.tier) - tierRank(a.tier));
  return [...stats.map((c) => ({ ...c, foot: `${TIER_NAME[c.tier]} tier` })), ...adv];
}

function PokeCard({ c }: { c: Card }) {
  const [tilt, setTilt] = useState<CSSProperties>({});
  const wrap = useRef<HTMLDivElement>(null);
  useEffect(() => (c.tier === 'SSS' && wrap.current ? attachGodRays(wrap.current) : undefined), [c.tier]);
  const interactive = tierRank(c.tier) >= tierRank('S');
  const move = (e: PointerEvent<HTMLDivElement>) => {
    if (!interactive) return;
    const r = e.currentTarget.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    setTilt({ '--ry': `${x * 24}deg`, '--rx': `${-y * 18}deg`, '--mx': `${(x + 0.5) * 100}%`, '--my': `${(y + 0.5) * 100}%` } as CSSProperties);
  };
  // The tilt lives on the wrapper so the SSS god rays, which reach outside the card, tilt with it.
  return (
    <div ref={wrap} className={`pk-wrap w-${c.tier} ${Object.keys(tilt).length ? 'pk-held' : ''}`} style={tilt} onPointerMove={move} onPointerLeave={() => setTilt({})}>
      {c.tier === 'SSS' && <span className="pk-dust" aria-hidden />}
      <div className={`pk-card tier-${c.tier}`}>
        <div className="pk-head"><span className="pk-title">{c.title}</span><span className="pk-tier">{c.tier}</span></div>
        <div className="pk-art"><PixelIcon name={c.icon} size={72} /></div>
        <div className="pk-kind">{c.kind}</div>
        <div className={`pk-value ${pixel.className}`}>{c.value}</div>
        {c.lines.map((l) => <div key={l} className="pk-line">{l}</div>)}
        <div className="pk-foot">{c.foot}</div>
      </div>
    </div>
  );
}

// Totals for the whole run: a one-line strip that expands into collectible cards.
export function Stats() {
  const [d, setD] = useState<StatsData | null>(null);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const db = browserDb();
    db.from('jc_stats').select('data').eq('id', 1).maybeSingle().then(({ data }) => data && setD(data.data as StatsData));
    const ch = db.channel('stats').on('postgres_changes', { event: '*', schema: 'public', table: 'jc_stats' },
      ({ new: row }) => (row as { data?: StatsData }).data && setD((row as { data: StatsData }).data)).subscribe();
    return () => { db.removeChannel(ch); };
  }, []);
  if (!d) return null;
  const t = d.totals;
  const chips: [IconName, string][] = [
    ['pickaxe', n(t.dug)], ['block', n(t.placed)], ['hammer', n(t.crafted)], ['sword', n(sum(t.kills))],
    ['skull', n(sum(t.deaths))], ['compass', `${(t.distance_blocks / 1000).toFixed(1)}km`], ['sun', `D${d.day}`], ['trophy', String(d.advancements.length)],
  ];
  return (
    <section className="rounded-2xl border border-white/10 bg-black/40">
      <button onClick={() => setOpen(!open)} aria-expanded={open}
        className={`flex w-full flex-wrap items-center gap-x-5 gap-y-2 px-4 py-3 text-left text-[11px] ${pixel.className}`}>
        {chips.map(([icon, v]) => (
          <span key={icon} className="inline-flex items-center gap-1.5 text-zinc-100"><PixelIcon name={icon} size={16} />{v}</span>
        ))}
        <span className="ml-auto text-lime-300">{open ? 'Hide cards ▴' : 'Stats ▾'}</span>
      </button>
      {open && (
        <div className="grid grid-cols-2 gap-5 border-t border-white/10 p-5 sm:grid-cols-3 lg:grid-cols-5">
          {cards(d).map((c) => <PokeCard key={c.key} c={c} />)}
        </div>
      )}
    </section>
  );
}
