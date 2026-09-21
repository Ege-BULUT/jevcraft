'use client';
import { useEffect, useState } from 'react';
import { browserDb, type Decision } from '@/lib/db';

// What Jev is doing in the game right now: the newest decision, pushed by realtime.
export function NowPlaying() {
  const [d, setD] = useState<Decision | null>(null);
  const [now, setNow] = useState(0);
  useEffect(() => {
    const db = browserDb();
    db.from('jc_decisions').select('*').order('at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => { setD(data as Decision | null); setNow(Date.now()); });
    const ch = db.channel('now').on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'jc_decisions' },
      ({ new: row }) => setD(row as Decision)).subscribe();
    const iv = setInterval(() => setNow(Date.now()), 5000);
    return () => { db.removeChannel(ch); clearInterval(iv); };
  }, []);
  if (!d) return null;
  const ago = Math.max(0, Math.round((now - Date.parse(d.at)) / 1000));
  const playing = ago < 180;
  const label = d.options.find((o) => o.id === d.action)?.label ?? d.action;
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-white/10 bg-black/40 px-4 py-3 text-sm">
      {playing
        ? <span className="inline-flex items-center gap-1.5 rounded bg-red-600 px-2 py-0.5 text-xs font-black uppercase tracking-widest"><span className="size-1.5 animate-pulse rounded-full bg-white" />In game now</span>
        : <span className="rounded bg-white/10 px-2 py-0.5 text-xs font-semibold uppercase tracking-widest text-zinc-300">Paused</span>}
      <span className="text-zinc-200">{label}</span>
      <span className="text-zinc-500">{ago < 90 ? `${ago}s ago` : `${Math.round(ago / 60)} min ago`}</span>
      {d.snapshot?.health != null && <span className="ml-auto font-mono text-zinc-300">❤ {d.snapshot.health} · 🍗 {d.snapshot.hunger ?? '–'}{d.snapshot.day != null ? ` · day ${d.snapshot.day}` : ''}</span>}
    </div>
  );
}
