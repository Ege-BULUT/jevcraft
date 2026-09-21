// Card tiers, from plain wood (F) to the animated holographic SSS.
export const TIERS = ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'] as const;
export type Tier = (typeof TIERS)[number];

// A stat's tier: the highest threshold its value has reached (one threshold per tier above F).
const THRESHOLDS: Record<string, number[]> = {
  dug:      [100, 500, 2_000, 5_000, 15_000, 40_000, 100_000, 250_000],
  placed:   [20, 100, 300, 1_000, 3_000, 8_000, 20_000, 50_000],
  crafted:  [20, 100, 300, 1_000, 3_000, 8_000, 20_000, 50_000],
  kills:    [5, 20, 50, 100, 250, 500, 1_000, 2_500],
  deaths:   [5, 20, 50, 100, 200, 400, 800, 1_500],
  km:       [1, 3, 10, 25, 50, 100, 200, 400],
  days:     [3, 7, 15, 30, 60, 100, 200, 365],
  diamond:  [1, 3, 8, 16, 32, 64, 128, 256],
  iron:     [5, 20, 50, 100, 250, 500, 1_000, 2_000],
  coal:     [10, 40, 100, 250, 500, 1_000, 2_500, 5_000],
  life_min: [5, 15, 30, 60, 120, 240, 480, 960],
};
export function statTier(kind: string, value: number): Tier {
  const t = THRESHOLDS[kind] ?? [];
  let i = 0;
  while (i < t.length && value >= t[i]) i++;
  return TIERS[i];
}

// VoxeLibre's advancements by how far into the game they are.
const ADVANCEMENT_TIER: Record<string, Tier> = {
  'Getting Wood': 'F', 'Benchmarking': 'F', 'Time to Mine!': 'F',
  'Hot Topic': 'E', 'Time to Farm!': 'E', 'Time to Strike!': 'E', 'Getting an Upgrade': 'E', 'Delicious Fish': 'E',
  'Pork Chop': 'E', 'Rabbit Season': 'E', 'Cow Tipper': 'E', 'Bake Bread': 'E',
  'Acquire Hardware': 'D', "Isn't It Iron Pick": 'D', 'The Lie': 'D', 'On A Rail': 'D', 'Sweet Dreams': 'D', 'Pot Planter': 'D',
  'Wax On': 'D', 'Wax Off': 'D', 'Librarian': 'D', 'Dispense With This': 'D', 'Tactical Fishing': 'D', 'Fishy Business': 'D',
  'Bee Our Guest': 'D', 'Crafting a New Look': 'D',
  'What A Deal!': 'C', 'The Haggler': 'C', 'Sniper Duel': 'C', "Who's Cutting Onions?": 'C', 'Total Beelocation': 'C',
  'Iron Belly': 'C', 'Smithing with Style': 'C', 'The Cutest Predator': 'C', 'Voluntary Exile': 'C',
  'DIAMONDS!': 'B', 'Hero of the Village': 'B', 'Playing with Fire': 'B',
  'We Need to Go Deeper': 'A', 'The Nether': 'A', 'Enchanter': 'A', 'Local Brewery': 'A', 'Hidden in the Depths': 'A',
  'Serious Dedication': 'A', 'Postmortal': 'A', 'Country Lode, Take Me Home': 'A', "Sky's the Limit": 'A',
  'The End?': 'S', 'Bring Home the Beacon': 'S', 'Withering Heights': 'S', 'The Next Generation': 'S',
  'The End... Again...': 'SS', 'Beaconator': 'SS',
  'Free the End': 'SSS',
};
export const advancementTier = (name: string): Tier => ADVANCEMENT_TIER[name] ?? 'C';
export const tierRank = (t: Tier) => TIERS.indexOf(t);
