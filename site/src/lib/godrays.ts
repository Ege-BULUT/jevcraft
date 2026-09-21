// Light shafts through the SSS badge. The badge letters are slots cut into the card; a light sits
// behind the card, and its beams escape through the slots as volumetric shafts. This is screen-space
// light scattering (the GPU Gems 3 technique) on a 2D canvas: the letter mask is drawn many times,
// scaled away from where the light projects on screen, with falling intensity. The light's projected
// position follows the card's real 3D rotation, so the shafts swing as the card turns.
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
  const PAD = 170;          // how far the shafts may reach past the card, in CSS px
  const DEPTH = 240;        // how far behind the card the light sits, in CSS px
  const SAMPLES = 56, STEP = 0.022, DECAY = 0.95;
  // An area light, not a point: a few sample positions spread the shafts into a soft fan.
  const LIGHTS: [number, number][] = [[-16, 4], [0, -6], [16, 4], [-6, 10], [8, -2]];
  let raf = 0, visible = true;

  const io = new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(raf);
    if (visible) raf = requestAnimationFrame(frame);
  });
  io.observe(wrap);

  function frame(now: number) {
    if (!visible) return;
    raf = requestAnimationFrame(frame);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const wr = wrap.getBoundingClientRect(), br = badge!.getBoundingClientRect();
    const W = wr.width + PAD * 2, H = wr.height + PAD * 2;
    if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
      canvas.width = mask.width = Math.round(W * dpr);
      canvas.height = mask.height = Math.round(H * dpr);
      Object.assign(canvas.style, { left: `${-PAD}px`, top: `${-PAD}px`, width: `${W}px`, height: `${H}px` });
    }
    // The slots: the badge letters, where the badge is on screen right now.
    const cx = br.left - wr.left + PAD + br.width / 2, cy = br.top - wr.top + PAD + br.height / 2;
    mctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    mctx.clearRect(0, 0, W, H);
    mctx.font = `900 ${Math.max(9, br.height * 0.64)}px system-ui, sans-serif`;
    mctx.textAlign = 'center';
    mctx.textBaseline = 'middle';
    const g = mctx.createLinearGradient(cx, cy - 8, cx, cy + 8);
    g.addColorStop(0, '#fffbe8'); g.addColorStop(1, '#ffc53a');
    mctx.fillStyle = g;
    mctx.fillText(badge!.textContent ?? '', cx, cy + 0.5);

    // Where the light behind the card lands on screen: the card's rotation tips it the other way.
    const m = new DOMMatrix(getComputedStyle(card!).transform);
    const flicker = 0.85 + 0.15 * Math.sin(now / 170) * Math.sin(now / 410);
    const lx = cx - m.m13 * DEPTH + Math.sin(now / 1300) * 8;
    const ly = cy + m.m23 * DEPTH + 26 + Math.cos(now / 1700) * 6;

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.globalCompositeOperation = 'lighter';
    ctx.filter = 'blur(1px)';
    for (const [jx, jy] of LIGHTS) {
      const px = (lx + jx) * dpr, py = (ly + jy) * dpr;
      let a = (0.34 / LIGHTS.length) * 2.2 * flicker;
      for (let i = 3; i <= SAMPLES; i++, a *= DECAY) {
        const s = 1 + i * STEP; // each copy pushed further from the light: the shaft
        ctx.globalAlpha = a;
        ctx.setTransform(s, 0, 0, s, px * (1 - s), py * (1 - s));
        ctx.drawImage(mask, 0, 0);
      }
    }
    // The slots themselves: a soft bloom, then the crisp letters burning white-gold.
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.filter = 'blur(2px)';
    ctx.globalAlpha = 0.45;
    ctx.drawImage(mask, 0, 0);
    ctx.filter = 'none';
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(mask, 0, 0);
  }

  return () => { cancelAnimationFrame(raf); io.disconnect(); canvas.remove(); };
}
