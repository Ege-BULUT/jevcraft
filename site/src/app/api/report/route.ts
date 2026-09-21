import { adminDb, authorised } from '@/lib/server';

// The poster stores each two-hourly report here, then records the id of the post that shared it.
export async function POST(req: Request) {
  if (!authorised(req)) return Response.json({ error: 'unauthorised' }, { status: 401 });
  const { data } = (await req.json().catch(() => ({}))) as { data?: unknown };
  if (!data || typeof data !== 'object' || JSON.stringify(data).length > 50_000) return Response.json({ error: 'bad request' }, { status: 400 });
  const r = await adminDb().from('jc_reports').insert({ data }).select('id').single();
  if (r.error) return Response.json({ error: r.error.message }, { status: 500 });
  return Response.json({ id: r.data.id });
}

export async function PATCH(req: Request) {
  if (!authorised(req)) return Response.json({ error: 'unauthorised' }, { status: 401 });
  const { id, tweet_id } = (await req.json().catch(() => ({}))) as { id?: unknown; tweet_id?: unknown };
  if (!Number.isInteger(id) || typeof tweet_id !== 'string' || !/^\d{1,25}$/.test(tweet_id)) return Response.json({ error: 'bad request' }, { status: 400 });
  await adminDb().from('jc_reports').update({ tweet_id }).eq('id', id);
  return Response.json({ ok: true });
}
