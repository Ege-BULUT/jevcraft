import { timingSafeEqual } from 'node:crypto';
import { experimental_evaluate as evaluate, InvalidResponseDataError } from 'ai';
import { GatewayRateLimitError } from '@ai-sdk/gateway';
import { adminDb } from '@/lib/server';

// Called by the jev_agent mod on the game machine: it sends the situation and the skills it can
// run now, Jev picks one. Only that machine holds the key, so nobody else can spend the budget.
const UNTIL = Date.parse(process.env.JEVCRAFT_UNTIL ?? '2026-09-25T21:00:00Z'); // end of 25 Sep, Istanbul
const DAILY_CAP_TOKENS = Math.floor(Number(process.env.JEVCRAFT_DAILY_CAP_USD ?? 1) / (0.042 / 1e6));

type Option = { id: string; label: string; detail: string };
type Body = { state?: unknown; options?: unknown; snapshot?: unknown };

const isOption = (o: unknown): o is Option => {
  const x = o as Option;
  return !!x && [x.id, x.label, x.detail].every((v) => typeof v === 'string') &&
    x.id.length <= 40 && x.label.length <= 60 && x.detail.length <= 400;
};

function authorised(req: Request) {
  const want = Buffer.from(process.env.JEVCRAFT_KEY ?? '');
  const got = Buffer.from(req.headers.get('x-jevcraft-key') ?? '');
  return want.length > 0 && got.length === want.length && timingSafeEqual(want, got);
}

export async function POST(req: Request) {
  if (!authorised(req)) return Response.json({ error: 'unauthorised' }, { status: 401 });
  if (Date.now() > UNTIL) return Response.json({ error: 'the run is over' }, { status: 410 });
  const { state, options, snapshot } = (await req.json().catch(() => ({}))) as Body;
  if (typeof state !== 'string' || state.length > 4000 || !Array.isArray(options) || options.length < 1 ||
      options.length > 24 || !options.every(isOption) || new Set(options.map((o) => o.id)).size !== options.length) {
    return Response.json({ error: 'bad request' }, { status: 400 });
  }

  const db = adminDb();
  const day = new Date().toISOString().slice(0, 10);
  const spent = (await db.from('jc_spend').select('input_tokens').eq('day', day).maybeSingle()).data?.input_tokens ?? 0;
  if (spent >= DAILY_CAP_TOKENS) return Response.json({ wait: true, retryMs: 10 * 60_000, reason: 'daily cap' });

  const criteria = Object.fromEntries(options.map((o) => [o.id, o.detail]));
  const t0 = Date.now();
  let probs: Record<string, number>, action: string, confidence: number | null = null, tokens: number;
  try {
    const r = await evaluate({
      model: 'typesafe-ai/jev',
      state,
      questions: { skill: { type: 'choice', instructions: 'You are playing a survival sandbox game. Which skill should you run next to survive, progress and eventually reach and defeat the ender dragon?', criteria } },
      maxRetries: 0,
    });
    action = r.answers.skill.choice;
    probs = r.answers.skill.probabilities ?? { [action]: 1 };
    confidence = (r.providerMetadata?.typesafe as { confidence?: Record<string, number> } | undefined)?.confidence?.skill ?? null;
    tokens = r.usage.inputTokens ?? Math.ceil((state.length + JSON.stringify(criteria).length) / 4);
  } catch (e) {
    if (GatewayRateLimitError.isInstance(e)) {
      const after = Number((e.cause as { responseHeaders?: Record<string, string> } | undefined)?.responseHeaders?.['retry-after']);
      return Response.json({ wait: true, retryMs: (Number.isFinite(after) && after > 0 ? after : 5) * 1000 });
    }
    // A tie or a partial distribution is still Jev's answer: take its top option.
    const p = InvalidResponseDataError.isInstance(e) ? (e.data as { skill?: { probabilities?: Record<string, number> } })?.skill?.probabilities : undefined;
    if (!p) return Response.json({ wait: true, retryMs: 3000, reason: (e as Error).message.slice(0, 200) });
    probs = Object.fromEntries(options.map((o) => [o.id, Number(p[o.id]) || 0]));
    action = Object.entries(probs).sort((a, b) => b[1] - a[1])[0][0];
    tokens = Math.ceil((state.length + JSON.stringify(criteria).length) / 4);
  }

  await Promise.all([
    db.from('jc_decisions').insert({ state, options, probs, action, confidence, latency_ms: Date.now() - t0, tokens, snapshot: snapshot ?? null }),
    db.rpc('jc_add_spend', { p_tokens: tokens }),
  ]);
  return Response.json({ action });
}
