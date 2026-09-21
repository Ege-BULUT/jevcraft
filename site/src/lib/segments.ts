import 'server-only';

export type Segment = { path: string; url: string; start: string }; // start: ISO time of the first frame

export const HF_REPO = process.env.HF_REPO ?? 'jevcraft/jevcraft';

// Segments are named after their UTC start, e.g. videos/2026-09-21/2026-09-21T083543Z.mp4.
const startOf = (name: string) =>
  name.replace(/^(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})(\d{2})Z\.mp4$/, '$1T$2:$3:$4Z');

export async function listSegments(): Promise<Segment[]> {
  const res = await fetch(`https://huggingface.co/api/datasets/${HF_REPO}/tree/main/videos?recursive=true`, {
    next: { revalidate: 15 },
  });
  if (!res.ok) return [];
  const items = (await res.json()) as { type: string; path: string }[];
  return items
    .filter((i) => i.type === 'file' && i.path.endsWith('.mp4'))
    .map((i) => ({
      path: i.path,
      url: `https://huggingface.co/datasets/${HF_REPO}/resolve/main/${i.path}`,
      start: startOf(i.path.split('/').pop()!),
    }))
    .sort((a, b) => a.start.localeCompare(b.start));
}
