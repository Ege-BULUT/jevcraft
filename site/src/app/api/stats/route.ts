import { adminDb, authorised } from '@/lib/server';

// The poster on the game machine pushes the run's running totals here every minute.
export async function POST(req: Request) {
  if (!authorised(req)) return Response.json({ error: 'unauthorised' }, { status: 401 });
  const { data } = (await req.json().catch(() => ({}))) as { data?: unknown };
  if (!data || typeof data !== 'object' || JSON.stringify(data).length > 50_000) return Response.json({ error: 'bad request' }, { status: 400 });
  const r = await adminDb().from('jc_stats').upsert({ id: 1, at: new Date().toISOString(), data });
  if (r.error) return Response.json({ error: r.error.message }, { status: 500 });
  return Response.json({ ok: true });
}
