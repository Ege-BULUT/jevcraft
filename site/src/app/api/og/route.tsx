import { ImageResponse } from 'next/og';
import { adminDb } from '@/lib/server';

// Share card: /api/og for the site, /api/og?report=<id> for one status update's numbers.
const time = (iso: string) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Istanbul' });
const date = (iso: string) => new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'Europe/Istanbul' });

type Stats = { deaths: number; distance_m: number; dug: number; placed: number; crafted: number; kills: Record<string, number> };
type Data = { from: string; to: string; hours: [number, number]; day: number; stats: Stats; biggest: { at: string; text: string } | null };

export async function GET(req: Request) {
  const id = new URL(req.url).searchParams.get('report');
  const data = id && /^\d+$/.test(id)
    ? ((await adminDb().from('jc_reports').select('data').eq('id', Number(id)).maybeSingle()).data?.data as Data | undefined)
    : undefined;

  const frame = (children: React.ReactNode) => (
    <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', padding: '56px 64px', color: '#ecefe6',
      background: 'linear-gradient(160deg, #1d2a10 0%, #0a0c08 55%, #2a1c0e 100%)', fontFamily: 'sans-serif' }}>
      <div style={{ display: 'flex', fontSize: 30, color: '#a3e635', fontWeight: 700 }}>🧱 JevCraft</div>
      {children}
      <div style={{ display: 'flex', marginTop: 'auto', fontSize: 26, color: '#a3a39a' }}>jevcraft.vercel.app · TypeSafe&apos;s Jev, live in a block world 24/7</div>
    </div>
  );

  if (!data) {
    return new ImageResponse(frame(
      <div style={{ display: 'flex', flexDirection: 'column', marginTop: 40 }}>
        <div style={{ display: 'flex', fontSize: 92, fontWeight: 800, lineHeight: 1.05 }}>Jev lives within</div>
        <div style={{ display: 'flex', fontSize: 92, fontWeight: 800, color: '#a3e635' }}>block world.</div>
        <div style={{ display: 'flex', fontSize: 32, marginTop: 28, color: '#cfd3c4', maxWidth: 900 }}>
          An AI that never talks chops, mines, crafts, fights and survives around the clock. Every minute is recorded.
        </div>
      </div>));
  }

  const s = data.stats, kills = Object.values(s.kills).reduce((a, b) => a + b, 0);
  const tiles: [string, string][] = [
    ['⛏', `${s.dug.toLocaleString('en')} dug`], ['🧱', `${s.placed} placed`], ['🛠', `${s.crafted} crafted`],
    ['⚔', `${kills} kills`], ['☠', `${s.deaths} deaths`], ['🧭', `~${(s.distance_m / 1000).toFixed(1)} km`],
  ];
  return new ImageResponse(frame(
    <div style={{ display: 'flex', flexDirection: 'column', marginTop: 18 }}>
      <div style={{ display: 'flex', fontSize: 44, fontWeight: 800 }}>
        Status update · {date(data.to)}, {time(data.from)}–{time(data.to)} GMT+3
      </div>
      <div style={{ display: 'flex', fontSize: 28, color: '#cfd3c4', marginTop: 6 }}>
        {data.hours[0] === data.hours[1] ? `Hour ${data.hours[0]}` : `Hours ${data.hours[0]}–${data.hours[1]}`} of the run · in-game day {data.day}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, marginTop: 30 }}>
        {tiles.map(([icon, text]) => (
          <div key={text} style={{ display: 'flex', alignItems: 'center', gap: 12, width: 340, padding: '18px 22px', borderRadius: 18,
            background: 'rgba(255,255,255,0.07)', fontSize: 36, fontWeight: 700 }}>
            <span>{icon}</span><span>{text}</span>
          </div>
        ))}
      </div>
      {data.biggest && (
        <div style={{ display: 'flex', marginTop: 26, fontSize: 34, color: '#d9f99d' }}>⭐ {data.biggest.text}, {time(data.biggest.at)} GMT+3</div>
      )}
    </div>));
}
