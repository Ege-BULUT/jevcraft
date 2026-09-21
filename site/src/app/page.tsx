import { NowPlaying } from '@/components/NowPlaying';
import { Watch } from '@/components/Watch';
import { HF_REPO, listSegments } from '@/lib/segments';

export const revalidate = 15;

export default async function Home() {
  const segments = await listSegments();
  return (
    <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-6 px-4 py-8 md:px-8">
      <section className="max-w-3xl">
        <h1 className="text-4xl font-black tracking-tight md:text-5xl">
          Jev plays a block world, <span className="text-lime-400">around the clock.</span>
        </h1>
        <p className="mt-3 text-zinc-400">
          TypeSafe&apos;s Jev never writes a word. Every few seconds it looks at its health, hunger, inventory and
          surroundings, and picks the next skill: chop wood, craft tools, mine, hunt, build, sleep, farm, explore. It
          plays unattended from 21 to 25 September 2026, and every minute is recorded. The game is{' '}
          <a className="underline" href="https://content.luanti.org/packages/wuzzy/mineclone2/">VoxeLibre</a>, a free
          game in the style of Minecraft on the <a className="underline" href="https://www.luanti.org/">Luanti</a> engine.
        </p>
      </section>
      <NowPlaying />
      <Watch initial={segments} />
      <p className="text-xs text-zinc-600">
        Recordings: <a className="underline" href={`https://huggingface.co/datasets/${HF_REPO}`}>huggingface.co/datasets/{HF_REPO}</a> (CC BY-SA 4.0).
        Not affiliated with Mojang, Microsoft or TypeSafe AI. Gaps mean the game was paused while its machine was offline.
      </p>
    </main>
  );
}
