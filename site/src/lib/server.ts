import 'server-only';
import { timingSafeEqual } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

export const adminDb = () =>
  createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, { auth: { persistSession: false } });

// Requests from the game machine carry the shared key; nothing else may spend or publish.
export function authorised(req: Request) {
  const want = Buffer.from(process.env.JEVCRAFT_KEY ?? '');
  const got = Buffer.from(req.headers.get('x-jevcraft-key') ?? '');
  return want.length > 0 && got.length === want.length && timingSafeEqual(want, got);
}
