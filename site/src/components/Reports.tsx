'use client';
import { useEffect, useState } from 'react';
import { browserDb } from '@/lib/db';

type Report = {
  id: number; at: string; tweet_id: string | null;
  data: {
    from: string; to: string; hours: [number, number]; day: number;
    stats: { deaths: number; causes: Record<string, number>; distance_m: number; dug: number; placed: number;
      crafts: Record<string, number>; crafted: number; kills: Record<string, number> };
    advancements: string[]; moments: { at: string; text: string }[]; biggest: { at: string; text: string } | null;
  };
};

const time = (iso: string) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Istanbul' });
const date = (iso: string) => new Date(iso).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Istanbul' });
const sorted = (o: Record<string, number>) => Object.entries(o).sort((a, b) => b[1] - a[1]);

// The two-hourly status updates: a list under the chat, and the full report in a modal (?report=<id>).
export function Reports({ open: initial }: { open?: number }) {
  const [reports, setReports] = useState<Report[]>([]);
  const [open, setOpen] = useState<number | null>(initial ?? null);
  useEffect(() => {
    browserDb().from('jc_reports').select('*').order('at', { ascending: false }).limit(60)
      .then(({ data }) => setReports((data ?? []) as Report[]));
  }, []);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(null); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  const shown = reports.find((r) => r.id === open);
  if (!reports.length) return null;

  return (
    <section className="rounded-2xl border border-white/10 bg-black/30 p-4">
      <h2 className="mb-3 text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Status updates · every two hours</h2>
      <div className="flex flex-wrap gap-2">
        {reports.map((r) => (
          <button key={r.id} onClick={() => setOpen(r.id)} className="rounded-lg border border-white/10 px-3 py-2 text-left text-sm hover:border-lime-400/60">
            <div className="font-semibold">{date(r.data.to)} · {time(r.data.from)}–{time(r.data.to)}</div>
            <div className="text-xs text-zinc-400">⛏ {r.data.stats.dug.toLocaleString('en')} · ☠ {r.data.stats.deaths}{r.data.biggest ? ` · ⭐ ${r.data.biggest.text}` : ''}</div>
          </button>
        ))}
      </div>

      {shown && (
        <div role="dialog" aria-modal="true" aria-label="Status report" onClick={() => setOpen(null)}
          className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 backdrop-blur-sm md:p-10">
          <article onClick={(e) => e.stopPropagation()} className="w-full max-w-2xl rounded-2xl border border-white/15 bg-zinc-950 p-6 shadow-2xl">
            <header className="mb-4 flex items-start justify-between gap-4">
              <div>
                <p className="text-xs uppercase tracking-[0.2em] text-lime-400">Status update</p>
                <h3 className="text-2xl font-black">{date(shown.data.to)}, {time(shown.data.from)}–{time(shown.data.to)} <span className="text-base font-normal text-zinc-400">GMT+3</span></h3>
                <p className="text-sm text-zinc-400">{shown.data.hours[0] === shown.data.hours[1] ? `Hour ${shown.data.hours[0]}` : `Hours ${shown.data.hours[0]}–${shown.data.hours[1]}`} of the run · in-game day {shown.data.day}</p>
              </div>
              <button onClick={() => setOpen(null)} aria-label="Close" className="rounded-full bg-white/10 px-3 py-1 text-lg hover:bg-white/20">×</button>
            </header>

            {shown.data.biggest && (
              <a href={`/?t=${shown.data.biggest.at}`} className="mb-4 block rounded-xl bg-lime-400/10 p-4 hover:bg-lime-400/20">
                <p className="text-xs uppercase tracking-widest text-lime-300">Biggest moment</p>
                <p className="text-lg font-bold">⭐ {shown.data.biggest.text} <span className="text-sm font-normal text-zinc-400">at {time(shown.data.biggest.at)} · watch ▶</span></p>
              </a>
            )}

            <dl className="mb-5 grid grid-cols-2 gap-2 sm:grid-cols-3">
              {[['⛏ Blocks dug', shown.data.stats.dug.toLocaleString('en')], ['🧱 Blocks placed', shown.data.stats.placed],
                ['🛠 Items crafted', shown.data.stats.crafted], ['⚔ Mobs killed', Object.values(shown.data.stats.kills).reduce((a, b) => a + b, 0)],
                ['☠ Deaths', shown.data.stats.deaths], ['🧭 Travelled', `~${(shown.data.stats.distance_m / 1000).toFixed(1)} km`]].map(([k, v]) => (
                <div key={k} className="rounded-lg bg-white/[0.05] p-3"><dt className="text-xs text-zinc-400">{k}</dt><dd className="text-xl font-bold tabular-nums">{v}</dd></div>
              ))}
            </dl>

            <div className="grid gap-5 sm:grid-cols-2">
              {[['Crafted', shown.data.stats.crafts], ['Killed', shown.data.stats.kills], ['Deaths', shown.data.stats.causes]].map(([title, obj]) =>
                Object.keys(obj as Record<string, number>).length > 0 && (
                  <div key={title as string}>
                    <h4 className="mb-1 text-xs font-semibold uppercase tracking-widest text-zinc-400">{title as string}</h4>
                    <ul className="text-sm text-zinc-200">{sorted(obj as Record<string, number>).map(([k, n]) => <li key={k}>{n}× {k}</li>)}</ul>
                  </div>
                ))}
              {shown.data.advancements.length > 0 && (
                <div>
                  <h4 className="mb-1 text-xs font-semibold uppercase tracking-widest text-zinc-400">Advancements</h4>
                  <ul className="text-sm text-zinc-200">{shown.data.advancements.map((a) => <li key={a}>🏆 {a}</li>)}</ul>
                </div>
              )}
            </div>

            {shown.data.moments.length > 0 && (
              <div className="mt-5">
                <h4 className="mb-1 text-xs font-semibold uppercase tracking-widest text-zinc-400">What happened</h4>
                <ol className="space-y-1 text-sm">
                  {shown.data.moments.map((m, i) => (
                    <li key={i}><a href={`/?t=${m.at}`} className="hover:text-lime-300"><span className="mr-2 font-mono text-xs text-zinc-500">{time(m.at)}</span>{m.text}</a></li>
                  ))}
                </ol>
              </div>
            )}
            {shown.tweet_id && <p className="mt-5 text-xs text-zinc-500"><a className="underline" href={`https://x.com/JevExperiments/status/${shown.tweet_id}`}>This update on X</a></p>}
          </article>
        </div>
      )}
    </section>
  );
}
