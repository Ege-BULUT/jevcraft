import 'server-only';
import { createClient } from '@supabase/supabase-js';

export const adminDb = () =>
  createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, { auth: { persistSession: false } });
