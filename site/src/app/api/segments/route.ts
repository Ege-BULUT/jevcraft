import { listSegments } from '@/lib/segments';

export async function GET() {
  return Response.json(await listSegments());
}
