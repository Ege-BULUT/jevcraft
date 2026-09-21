import { listSegments } from '@/lib/segments';

export const dynamic = 'force-dynamic'; // the list grows every two minutes; never serve a build-time copy

export async function GET() {
  return Response.json(await listSegments());
}
