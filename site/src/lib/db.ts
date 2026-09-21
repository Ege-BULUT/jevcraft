import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export type Option = { id: string; label: string; detail: string };
export type Decision = {
  id: number; at: string; state: string; options: Option[]; probs: Record<string, number>; action: string;
  confidence: number | null; latency_ms: number; tokens: number;
  snapshot: { health?: number; hunger?: number; pos?: { x: number; y: number; z: number }; dimension?: string; day?: number } | null;
};

let db: SupabaseClient | null = null;
// Anon key: read-only through RLS, plus realtime.
export const browserDb = () =>
  (db ??= createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!));
