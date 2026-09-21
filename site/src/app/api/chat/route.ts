import { adminDb } from '@/lib/server';
import { LINK, clean, ipHash, tidy } from '@/lib/chat';

// Posts one chat message. Spam protection: one message per 4 s and 20 per 10 min per sender,
// no links, no repeating your last message, length limits; profanity is replaced with ****.
export async function POST(req: Request) {
  const { name, body } = (await req.json().catch(() => ({}))) as { name?: unknown; body?: unknown };
  if (typeof name !== 'string' || typeof body !== 'string') return Response.json({ error: 'Name and message are required.' }, { status: 400 });
  const n = tidy(name), b = tidy(body);
  if (n.length < 1 || n.length > 24) return Response.json({ error: 'Names are 1–24 characters.' }, { status: 400 });
  if (b.length < 1 || b.length > 280) return Response.json({ error: 'Messages are 1–280 characters.' }, { status: 400 });
  if (LINK.test(b) || LINK.test(n)) return Response.json({ error: 'Links are not allowed in chat.' }, { status: 400 });

  const db = adminDb();
  const ip = ipHash(req);
  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const { data: recent } = await db.from('jc_chat').select('at, body').eq('ip_hash', ip).gte('at', since)
    .order('at', { ascending: false }).limit(20);
  if (recent?.length) {
    if (Date.now() - Date.parse(recent[0].at) < 4000) return Response.json({ error: 'Slow down a little.' }, { status: 429 });
    if (recent.length >= 20) return Response.json({ error: 'Too many messages; try again in a few minutes.' }, { status: 429 });
    if (recent[0].body === clean(b)) return Response.json({ error: 'You just said that.' }, { status: 429 });
  }

  const row = { name: clean(n), body: clean(b), ip_hash: ip };
  const { error } = await db.from('jc_chat').insert(row);
  if (error) return Response.json({ error: 'Could not post; try again.' }, { status: 500 });
  return Response.json({ ok: true });
}
