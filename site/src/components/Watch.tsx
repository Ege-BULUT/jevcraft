'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { browserDb, type Decision } from '@/lib/db';
import type { Segment } from '@/lib/segments';

const SEGMENT_S = 120; // the recorder's segment length
// One fixed locale and zone (the machine's, Istanbul), so the server render and the browser agree.
const TZ = { locale: 'en-GB', timeZone: 'Europe/Istanbul' } as const;
const hhmm = (iso: string) => new Date(iso).toLocaleTimeString(TZ.locale, { hour: '2-digit', minute: '2-digit', timeZone: TZ.timeZone });
const day = (iso: string) => new Date(iso).toLocaleDateString(TZ.locale, { weekday: 'short', day: 'numeric', month: 'short', timeZone: TZ.timeZone });

export function Watch({ initial, at }: { initial: Segment[]; at?: string }) {
  const [segments, setSegments] = useState(initial);
  const [idx, setIdx] = useState(Math.max(0, initial.length - 1));
  const [front, setFront] = useState<0 | 1>(0); // which of the two players is on screen
  const [live, setLive] = useState(!at);        // follow the newest segment, a few minutes behind the game
  const [waiting, setWaiting] = useState(false); // live and at the end: the next segment is still uploading
  const [playing, setPlaying] = useState(true);
  const [t, setT] = useState(0);
  const [decisions, setDecisions] = useState<Decision[]>([]);
  const [loaded, setLoaded] = useState(false);
  const playerA = useRef<HTMLVideoElement>(null), playerB = useRef<HTMLVideoElement>(null);
  const el = (p: 0 | 1) => (p === 0 ? playerA : playerB).current;
  const seekTo = useRef<number | null>(null); // offset to apply once the front player has the segment
  const seg = segments[idx];

  // Two players, one on screen and one preloading the next segment, so one segment ends and the
  // next starts without a gap: the recording plays as one continuous video.
  const srcOf = (p: 0 | 1) => segments[p === front ? idx : idx + 1]?.url;
  const advance = () => {
    if (idx + 1 >= segments.length) { if (live) setWaiting(true); return; }
    el(front === 0 ? 1 : 0)?.play().catch(() => {});
    setFront(front === 0 ? 1 : 0);
    setIdx(idx + 1);
    setT(0);
  };

  // New segments are appended every two minutes. The page may be a cached render, so fetch at once.
  useEffect(() => {
    const poll = async () => {
      const r = await fetch('/api/segments', { cache: 'no-store' }).catch(() => null);
      if (!r?.ok) return;
      const next = (await r.json()) as Segment[];
      setSegments(next);
      if (!loaded) {
        setLoaded(true);
        const want = at ? Date.parse(at) : NaN;
        if (!Number.isNaN(want) && next.length) {
          // The segment that covers that moment, or the last one before it (a pause leaves gaps).
          let i = 0;
          next.forEach((s, k) => { if (Date.parse(s.start) <= want) i = k; });
          seekTo.current = Math.max(0, Math.min(SEGMENT_S - 1, (want - Date.parse(next[i].start)) / 1000));
          setT(seekTo.current);
          setIdx(i);
        } else if (live) setIdx(Math.max(0, next.length - 1));
      }
    };
    if (!loaded) poll();
    const iv = setInterval(poll, 20_000);
    return () => clearInterval(iv);
  }, [loaded, live, at]);

  // Jump anywhere on the whole timeline: pick the segment, then the second within it.
  const jump = (sec: number, follow = false) => {
    const i = Math.max(0, Math.min(segments.length - 1, Math.floor(sec / SEGMENT_S)));
    seekTo.current = sec - i * SEGMENT_S;
    setT(seekTo.current); // keep the controlled slider on the new spot until the player catches up
    setLive(follow); setWaiting(false); setPlaying(true);
    const v = el(front);
    if (i === idx && v) { v.currentTime = seekTo.current; seekTo.current = null; }
    else setIdx(i);
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

  if (!seg) {
    return (
      <div className="rounded-2xl border border-white/10 bg-black/40 p-10 text-center text-zinc-400">
        The first recording is on its way: the game plays a few minutes ahead of what appears here.
      </div>
    );
  }

  const total = segments.length * SEGMENT_S;
  const position = idx * SEGMENT_S + t;
  const togglePlay = () => {
    const v = el(front);
    if (!v) return;
    if (v.paused) { v.play().catch(() => {}); setPlaying(true); } else { v.pause(); setPlaying(false); }
  };

  return (
    <div className="flex flex-col gap-5 lg:flex-row">
      <div className="lg:w-[64%]">
        <div className="relative aspect-video w-full overflow-hidden rounded-2xl border border-white/10 bg-black">
          {([0, 1] as const).map((p) => (
            <video
              key={p} ref={p === 0 ? playerA : playerB} src={srcOf(p)} muted playsInline preload="auto" autoPlay={p === front}
              className={`absolute inset-0 h-full w-full ${p === front ? 'opacity-100' : 'opacity-0'}`}
              onLoadedData={() => {
                // Caught up and the next segment has just arrived and loaded: carry on.
                if (p !== front && waiting) { setWaiting(false); advance(); }
              }}
              onLoadedMetadata={(e) => {
                if (p !== front) return;
                if (seekTo.current != null) { e.currentTarget.currentTime = seekTo.current; seekTo.current = null; }
                if (playing) e.currentTarget.play().catch(() => {});
              }}
              onTimeUpdate={(e) => { if (p === front) setT(e.currentTarget.currentTime); }}
              onEnded={() => { if (p === front) advance(); }}
            />
          ))}
          {waiting && <div className="absolute bottom-3 left-3 rounded bg-black/70 px-2 py-1 text-xs text-zinc-300">Caught up with the game: the next two minutes are uploading…</div>}
        </div>
        <div className="mt-2 flex items-center gap-3 text-xs text-zinc-400">
          <button onClick={togglePlay} aria-label={playing ? 'Pause' : 'Play'} className="grid size-8 shrink-0 place-items-center rounded-full bg-white/10 hover:bg-white/20">{playing ? '❚❚' : '▶'}</button>
          <input type="range" min={0} max={total} step={1} value={Math.min(position, total)} aria-label="Recording timeline"
            onChange={(e) => jump(Number(e.target.value))} className="w-full accent-lime-400" />
          <button onClick={() => jump(Math.max(0, total - SEGMENT_S), true)}
            className={`inline-flex shrink-0 items-center gap-1.5 rounded px-2 py-1 font-black uppercase tracking-widest ${live ? 'bg-red-600 text-white' : 'bg-white/10 text-zinc-300 hover:bg-white/20'}`}>
            <span className={`size-1.5 rounded-full ${live ? 'animate-pulse bg-white' : 'bg-zinc-400'}`} />Live
          </button>
        </div>
        <div className="mt-1 flex justify-between font-mono text-[11px] text-zinc-500">
          <span>{day(segments[0].start)} {hhmm(segments[0].start)}</span>
          <span className="text-zinc-300">{day(seg.start)} {new Date(now).toLocaleTimeString(TZ.locale, { timeZone: TZ.timeZone })} Istanbul time</span>
          <span>{hhmm(segments.at(-1)!.start)}</span>
        </div>
      </div>
      <aside className="rounded-2xl border border-white/10 bg-black/40 p-4 lg:w-[36%]">
        <DecisionView d={current} />
      </aside>
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
        <span className="font-mono text-xs text-zinc-500">{new Date(d.at).toLocaleTimeString(TZ.locale, { timeZone: TZ.timeZone })} · {d.latency_ms} ms</span>
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
