// Tiny original pixel-art icons, 8x8, drawn as SVG rects so they stay crisp at any size.
const PALETTE: Record<string, string> = {
  G: '#5fb832', g: '#4c9a28', D: '#8b5a2b', d: '#6d4420', W: '#eeeeee', K: '#222222', k: '#444444',
  S: '#c8ced6', s: '#9aa3ad', Y: '#f5c542', y: '#c99a1c', R: '#e0443a', r: '#a8261e', C: '#5ce1e6', c: '#2bb5c0', w: '#9a6634',
};

const ICONS = {
  pickaxe: ['..SSSS..', '.S....S.', 'S..w...S', '...w....', '..w.....', '.w......', 'w.......', '........'],
  block: ['GGGGGGGG', 'GgGGgGGg', 'DdDDdDDd', 'DDdDDDdD', 'dDDDdDDD', 'DDdDDDdD', 'DdDDDdDD', 'DDDdDDDd'],
  skull: ['.WWWWWW.', 'WWWWWWWW', 'WKKWWKKW', 'WKKWWKKW', 'WWWKKWWW', '.WWWWWW.', '.W.W.W..', '........'],
  sword: ['......SS', '.....SSS', '....SSS.', '.y.SSS..', '..ySS...', '..wy....', '.w..y...', 'w.......'],
  compass: ['..YYYY..', '.Y....Y.', 'Y..RR..Y', 'Y..RR..Y', 'Y..WW..Y', 'Y..WW..Y', '.Y....Y.', '..YYYY..'],
  trophy: ['Y.YYYY.Y', 'Y.YYYY.Y', '.YYYYYY.', '..YYYY..', '...YY...', '...yy...', '..YYYY..', '.YYYYYY.'],
  sun: ['...Y....', '.Y.Y.Y..', '..YYY...', 'YYYYYYY.', '..YYY...', '.Y.Y.Y..', '...Y....', '........'],
  hammer: ['.SSSS...', '.SSSSS..', '.SSSS...', '...w....', '...w....', '...w....', '...w....', '...w....'],
  diamond: ['........', '..CCCC..', '.CcCCcC.', 'CCCCCCCC', '.CCcCCC.', '..CCCC..', '...CC...', '........'],
  iron: ['........', '........', '..SSSS..', '.SsSSSS.', 'SSSSSSSS', 'SSSSsSSS', 'ssssssss', '........'],
  coal: ['........', '..KK....', '.KKkK...', 'KKKKKKk.', '.KkKKKK.', '..KKKK..', '...KK...', '........'],
  heart: ['........', '.RR.RR..', 'RRRRRRR.', 'RRRRRRr.', '.RRRRr..', '..RRr...', '...r....', '........'],
} as const;
export type IconName = keyof typeof ICONS;

export function PixelIcon({ name, size = 16, className }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 8 8" shapeRendering="crispEdges" className={className} aria-hidden>
      {ICONS[name].flatMap((row, y) => [...row].map((ch, x) => (ch === '.' ? null :
        <rect key={`${x}-${y}`} x={x} y={y} width={1} height={1} fill={PALETTE[ch]} />)))}
    </svg>
  );
}
