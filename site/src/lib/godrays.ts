// Light shafts through the SSS badge. The badge letters are slots cut into the card; a light sits
// behind the card, and its beams escape through the slots as volumetric shafts. This is screen-space
// light scattering (the GPU Gems 3 technique) on a 2D canvas: the letter mask is drawn many times,
// scaled away from where the light projects on screen, with falling intensity. The light's projected
// position follows the card's real 3D rotation, so the shafts swing as the card turns.
//
// Kept cheap: the shafts are drawn at a quarter of the pixels (the browser's upscale is the blur, so
// no canvas filter), each copy draws only the small letter mask, and it runs at 30 fps while visible.
// The crisp letters are the badge's own text.
export function attachGodRays(wrap: HTMLElement): () => void {
  const card = wrap.querySelector<HTMLElement>('.pk-card');
  const badge = wrap.querySelector<HTMLElement>('.pk-tier');
  if (!card || !badge) return () => {};
  const canvas = document.createElement('canvas');
  canvas.className = 'pk-rays-canvas';
  canvas.setAttribute('aria-hidden', 'true');
  wrap.appendChild(canvas);
  const mask = document.createElement('canvas');
  const ctx = canvas.getContext('2d')!, mctx = mask.getContext('2d')!;
  const PAD = 150;          // how far the shafts may reach past the card, in CSS px
  const DEPTH = 240;        // how far behind the card the light sits, in CSS px
  const RES = 0.5;          // canvas pixels per CSS px: a quarter of the pixels, and a free soft blur
  const SAMPLES = 32, STEP = 0.038, DECAY = 0.91, INTENSITY = 0.22;
  const LIGHTS: [number, number][] = [[-14, 5], [0, -5], [14, 5]]; // an area light, sampled at three points
  let raf = 0, visible = true, last = 0;

  const io = new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(raf);
    if (visible) raf = requestAnimationFrame(frame);
  });
  io.observe(wrap);

  function frame(now: number) {
    if (!visible) return;
    raf = requestAnimationFrame(frame);
    if (now - last < 33) return; // 30 fps is plenty for light
    last = now;
    const wr = wrap.getBoundingClientRect(), br = badge!.getBoundingClientRect();
    const W = wr.width + PAD * 2, H = wr.height + PAD * 2;
    if (canvas.width !== Math.round(W * RES) || canvas.height !== Math.round(H * RES)) {
      canvas.width = Math.round(W * RES);
      canvas.height = Math.round(H * RES);
      Object.assign(canvas.style, { left: `${-PAD}px`, top: `${-PAD}px`, width: `${W}px`, height: `${H}px` });
    }
    // The slots: the badge letters, in a small mask around the badge.
    const mx = br.left - wr.left + PAD - 4, my = br.top - wr.top + PAD - 4, mw = br.width + 8, mh = br.height + 8;
    if (mask.width !== Math.ceil(mw) || mask.height !== Math.ceil(mh)) { mask.width = Math.ceil(mw); mask.height = Math.ceil(mh); }
    mctx.clearRect(0, 0, mask.width, mask.height);
    mctx.font = `900 ${Math.max(9, br.height * 0.64)}px system-ui, sans-serif`;
    mctx.textAlign = 'center';
    mctx.textBaseline = 'middle';
    mctx.fillStyle = '#ffd98a';
    mctx.fillText(badge!.textContent ?? '', mw / 2, mh / 2 + 0.5);

    // Where the light behind the card lands on screen: the card's rotation tips it the other way.
    const m = new DOMMatrix(getComputedStyle(card!).transform);
    const cx = mx + mw / 2, cy = my + mh / 2;
    const lx = cx - m.m13 * DEPTH + Math.sin(now / 1300) * 8;
    const ly = cy + m.m23 * DEPTH + 26 + Math.cos(now / 1700) * 6;
    const flicker = 0.88 + 0.12 * Math.sin(now / 170) * Math.sin(now / 410);

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.globalCompositeOperation = 'lighter';
    for (const [jx, jy] of LIGHTS) {
      const px = lx + jx, py = ly + jy;
      let a = (INTENSITY / LIGHTS.length) * flicker;
      for (let i = 2; i <= SAMPLES; i++, a *= DECAY) {
        const s = 1 + i * STEP; // each copy pushed further from the light: the shaft
        ctx.globalAlpha = a;
        ctx.drawImage(mask, (px + (mx - px) * s) * RES, (py + (my - py) * s) * RES, mw * s * RES, mh * s * RES);
      }
    }
    // A soft bloom right at the slots.
    ctx.globalAlpha = 0.35 * flicker;
    ctx.drawImage(mask, mx * RES, my * RES, mw * RES, mh * RES);
    ctx.globalAlpha = 1;
  }

  return () => { cancelAnimationFrame(raf); io.disconnect(); canvas.remove(); };
}
