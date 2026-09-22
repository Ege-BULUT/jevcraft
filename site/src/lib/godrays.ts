// Light shafts through the SSS badge. The badge letters are slots cut into the card; a light sits
// behind the card, and its beams escape through the slots as volumetric shafts. This is screen-space
// light scattering (the GPU Gems 3 technique) on a 2D canvas: the letter mask is drawn many times,
// scaled away from where the light projects on screen, with falling intensity. The light's projected
// position follows the card's 3D rotation, so the shafts swing as the card turns.
//
// Kept cheap:
// - no DOM reads per frame. Reading the card's live transform or bounding box every frame made the
//   browser recompute style (73 times a second, 21% of the main thread). The badge's place is measured
//   once (and on resize); the card's angle is computed from the sway animation's clock, or taken from
//   the pointer tilt the page itself sets on the wrapper;
// - the shafts are drawn at a quarter of the pixels (the browser's upscale is the blur, no canvas
//   filter), each copy draws only the small letter mask, and it runs at 30 fps while visible, on a timer.
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
  const SWAY_MS = 5000;     // must match the pk-sway animation in globals.css
  const deg = Math.PI / 180;
  let timer = 0, visible = true, swayStart = 0, nextSwayCheck = 0;
  // Layout, measured without transforms (offset*), so it is stable while the card moves.
  let bx = 0, by = 0, dx = 0, dy = 0, mw = 0, mh = 0;

  function offsetIn(el: HTMLElement) { // position of el's border box inside wrap, ignoring transforms
    let x = 0, y = 0, e: HTMLElement | null = el;
    while (e && e !== wrap) {
      x += e.offsetLeft; y += e.offsetTop;
      const p = e.offsetParent as HTMLElement | null;
      if (p && p !== wrap) { x += p.clientLeft; y += p.clientTop; }
      e = p;
    }
    return [x, y];
  }
  function measure() {
    const [ox, oy] = offsetIn(badge!), [cxo, cyo] = offsetIn(card!);
    const bw = badge!.offsetWidth, bh = badge!.offsetHeight;
    bx = ox + bw / 2; by = oy + bh / 2;
    dx = bx - (cxo + card!.offsetWidth / 2); dy = by - (cyo + card!.offsetHeight / 2);
    mw = bw + 8; mh = bh + 8;
    const W = wrap.offsetWidth + PAD * 2, H = wrap.offsetHeight + PAD * 2;
    canvas.width = Math.round(W * RES); canvas.height = Math.round(H * RES);
    Object.assign(canvas.style, { left: `${-PAD}px`, top: `${-PAD}px`, width: `${W}px`, height: `${H}px` });
    mask.width = Math.ceil(mw); mask.height = Math.ceil(mh);
    mctx.clearRect(0, 0, mask.width, mask.height);
    mctx.font = `900 ${Math.max(9, bh * 0.64)}px system-ui, sans-serif`;
    mctx.textAlign = 'center';
    mctx.textBaseline = 'middle';
    mctx.fillStyle = '#ffd98a';
    mctx.fillText(badge!.textContent ?? '', mw / 2, mh / 2 + 0.5);
  }
  const ro = new ResizeObserver(measure);
  ro.observe(wrap);

  // The card's angle now, in degrees: the pointer tilt when held, else the sway animation's pose.
  function angles(now: number): [number, number] {
    if (wrap.classList.contains('pk-held')) {
      return [parseFloat(wrap.style.getPropertyValue('--ry')) || 0, parseFloat(wrap.style.getPropertyValue('--rx')) || 0];
    }
    if (now > nextSwayCheck) { // the sway restarts after a hover; pick up its start time now and then
      const a = card!.getAnimations().find((x) => (x as CSSAnimation).animationName === 'pk-sway');
      swayStart = typeof a?.startTime === 'number' ? a.startTime : swayStart;
      nextSwayCheck = now + 1000;
    }
    const p = (((now - swayStart) % SWAY_MS) + SWAY_MS) % SWAY_MS / SWAY_MS;
    const e = (x: number) => 0.5 - 0.5 * Math.cos(Math.PI * x); // close to ease-in-out
    const k = p < 0.5 ? e(p / 0.5) : 1 - e((p - 0.5) / 0.5);
    return [-16 + 32 * k, 5 - 10 * k]; // pk-sway: rotateY -16..16, rotateX 5..-5
  }

  // A plain 30 fps timer, not requestAnimationFrame: an rAF loop wakes the main thread every display
  // frame, and on each of those wakeups the browser also ticks every CSS animation on the page.
  const io = new IntersectionObserver(([en]) => {
    visible = en.isIntersecting;
    clearTimeout(timer);
    if (visible) frame();
  });
  io.observe(wrap);

  function frame() {
    if (!visible) return;
    timer = window.setTimeout(frame, 33); // 30 fps is plenty for light
    if (!mw) return;
    const now = performance.now(); // shares its origin with the animation timeline
    const [ry, rx] = angles(now);
    // The badge as seen through the card's rotation, and where the light behind the card lands.
    const cx = PAD + bx - dx + dx * Math.cos(ry * deg), cy = PAD + by - dy + dy * Math.cos(rx * deg);
    const mx = cx - mw / 2, my = cy - mh / 2;
    const lx = cx + Math.sin(ry * deg) * DEPTH + Math.sin(now / 1300) * 8;
    const ly = cy + Math.sin(rx * deg) * DEPTH + 26 + Math.cos(now / 1700) * 6;
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

  return () => { clearTimeout(timer); io.disconnect(); ro.disconnect(); canvas.remove(); };
}
