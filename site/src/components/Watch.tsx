'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { browserDb, type Decision } from '@/lib/db';
import type { Segment } from '@/lib/segments';

const SEGMENT_S = 120; // the recorder's segment length
const hhmm = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
const day = (iso: string) => new Date(iso).toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });

export function Watch({ initial }: { initial: Segment[] }) {
  const [segments, setSegments] = useState(initial);
  const [idx, setIdx] = useState(Math.max(0, initial.length - 1));
  const [live, setLive] = useState(true); // follow the newest segment, like a live stream a few minutes behind
  const [waiting, setWaiting] = useState(false); // live and at the end: the next segment is still uploading
  const [t, setT] = useState(0);
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const video = useRef<HTMLVideoElement>(null);
  const seg = segments[idx];

  // A new segment lands every two minutes; pick them up so playback runs on. A live viewer waiting
  // at the end moves to the new segment as soon as it appears.
  // The page itself may be a cached render from before the newest segments, so fetch right away.
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    const poll = async () => {
      const r = await fetch('/api/segments', { cache: 'no-store' }).catch(() => null);
      if (!r?.ok) return;
      const next = (await r.json()) as Segment[];
      setSegments(next);
      if (!loaded) { setLoaded(true); if (live) setIdx(Math.max(0, next.length - 1)); }
      else if (waiting && next.length - 1 > idx) { setWaiting(false); setIdx(idx + 1); }
    };
    if (!loaded) poll();
    const iv = setInterval(poll, 20_000);
    return () => clearInterval(iv);
  }, [idx, waiting, loaded, live]);

  const pick = (i: number) => { setLive(false); setWaiting(false); setIdx(i); };
  const goLive = () => { setLive(true); setWaiting(false); setIdx(segments.length - 1); };
  const ended = () => {
    if (idx < segments.length - 1) setIdx(idx + 1);
    else if (live) setWaiting(true);
  };

  // The decisions made while this segment was recorded.
  useEffect(() => {
    if (!seg) return;
    const from = new Date(Date.parse(seg.start) - 5 * 60_000).toISOString();
    const to = new Date(Date.parse(seg.start) + (SEGMENT_S + 60) * 1000).toISOString();
    browserDb().from('jc_decisions').select('*').gte('at', from).lte('at', to).order('at')
      .then(({ data }) => setDecisions((data ?? []) as Decision[]));
  }, [seg]);

  const now = seg ? Date.parse(seg.start) + t * 1000 : 0;
  const current = useMemo(() => [...decisions].reverse().find((d) => Date.parse(d.at) <= now) ?? null, [decisions, now]);
  const days = useMemo(() => [...new Set(segments.map((s) => day(s.start)))], [segments]);
  const [openDay, setOpenDay] = useState<string | null>(null);
  const shownDay = openDay ?? (seg ? day(seg.start) : days.at(-1));

  if (!seg) {
    return (
      <div className="rounded-2xl border border-white/10 bg-black/40 p-10 text-center text-zinc-400">
        The first recording is on its way: the game plays a few minutes ahead of what appears here.
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-5 lg:flex-row">
        <div className="lg:w-[64%]">
          <video
            ref={video} key={seg.url} src={seg.url} controls autoPlay muted playsInline
            onTimeUpdate={(e) => setT(e.currentTarget.currentTime)}
            onEnded={ended}
            className="aspect-video w-full rounded-2xl border border-white/10 bg-black"
          />
          {waiting && <p className="mt-2 text-xs text-zinc-400">Caught up with the game: the next two minutes are uploading…</p>}
          <div className="mt-2 flex items-center justify-between text-xs text-zinc-400">
            <span className="flex items-center gap-2">
              <button onClick={goLive} className={`inline-flex items-center gap-1.5 rounded px-2 py-1 font-black uppercase tracking-widest ${live ? 'bg-red-600 text-white' : 'bg-white/10 text-zinc-300 hover:bg-white/20'}`}>
                <span className={`size-1.5 rounded-full ${live ? 'animate-pulse bg-white' : 'bg-zinc-400'}`} />Live
              </button>
              {day(seg.start)} · {hhmm(seg.start)}–{hhmm(new Date(Date.parse(seg.start) + SEGMENT_S * 1000).toISOString())}</span>
            <span className="flex gap-2">
              <button className="rounded bg-white/10 px-2 py-1 hover:bg-white/20 disabled:opacity-40" disabled={idx === 0} onClick={() => pick(idx - 1)}>◀ Previous</button>
              <button className="rounded bg-white/10 px-2 py-1 hover:bg-white/20 disabled:opacity-40" disabled={idx >= segments.length - 1} onClick={() => pick(idx + 1)}>Next ▶</button>
            </span>
          </div>
        </div>
        <aside className="rounded-2xl border border-white/10 bg-black/40 p-4 lg:w-[36%]">
          <DecisionView d={current} />
        </aside>
      </div>

      <section className="rounded-2xl border border-white/10 bg-black/30 p-4">
        <div className="mb-3 flex flex-wrap gap-2">
          {days.map((d) => (
            <button key={d} onClick={() => setOpenDay(d)}
              className={`rounded-full px-3 py-1 text-sm ${d === shownDay ? 'bg-lime-400 text-black' : 'bg-white/10 text-zinc-300 hover:bg-white/20'}`}>{d}</button>
          ))}
        </div>
        <div className="flex flex-wrap gap-1.5">
          {segments.map((s, i) => day(s.start) === shownDay && (
            <button key={s.path} onClick={() => pick(i)}
              className={`rounded px-2 py-1 font-mono text-xs ${i === idx ? 'bg-lime-400 text-black' : 'bg-white/[0.06] text-zinc-300 hover:bg-white/15'}`}>{hhmm(s.start)}</button>
          ))}
        </div>
      </section>
    </div>
  );
}

export function DecisionView({ d }: { d: Decision | null }) {
  if (!d) return <p className="text-sm text-zinc-500">No decision yet at this point of the recording.</p>;
  const rows = [...d.options].sort((a, b) => (d.probs[b.id] ?? 0) - (d.probs[a.id] ?? 0)).slice(0, 8);
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-baseline justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Jev&apos;s choice</h3>
        <span className="font-mono text-xs text-zinc-500">{new Date(d.at).toLocaleTimeString()} · {d.latency_ms} ms</span>
      </div>
      <ul className="flex flex-col gap-1.5">
        {rows.map((o) => {
          const p = d.probs[o.id] ?? 0, chosen = o.id === d.action;
          return (
            <li key={o.id} title={o.detail} className={`relative h-9 overflow-hidden rounded-lg border ${chosen ? 'border-white/60' : 'border-white/10'} bg-white/[0.04]`}>
              <div className="absolute inset-y-0 left-0 transition-[width] duration-300" style={{ width: `${Math.max(p * 100, 0.5)}%`, background: chosen ? '#a3e635' : '#a3e63544' }} />
              <div className="relative flex h-full items-center justify-between px-3 text-sm">
                <span className={chosen ? 'font-semibold text-black' : 'text-zinc-200'}>{o.label}</span>
                <span className={`font-mono tabular-nums ${chosen ? 'text-black' : 'text-zinc-300'}`}>{(p * 100).toFixed(1)}%</span>
              </div>
            </li>
          );
        })}
      </ul>
      <p className="text-sm text-zinc-300">{d.options.find((o) => o.id === d.action)?.detail}</p>
      <details className="text-xs text-zinc-500">
        <summary className="cursor-pointer">What Jev saw</summary>
        <pre className="mt-2 whitespace-pre-wrap font-mono text-[11px] leading-relaxed">{d.state}</pre>
      </details>
    </div>
  );
}
