import 'server-only';
import { createHash } from 'node:crypto';
import { RegExpMatcher, TextCensor, englishDataset, englishRecommendedTransformers, fixedPhraseCensorStrategy } from 'obscenity';

// English profanity, including leetspeak and look-alike characters, from obscenity's dataset.
const matcher = new RegExpMatcher({ ...englishDataset.build(), ...englishRecommendedTransformers });
const censor = new TextCensor().setStrategy(fixedPhraseCensorStrategy('****'));

// The site's audience is partly Turkish, and the dataset is English only.
// \b only knows ASCII letters, so word edges are Unicode letter lookarounds (ç, ğ, ş end words too).
const TURKISH = /(?<![\p{L}\p{N}])(amk|aq|orospu\p{L}*|siktir\p{L}*|sik(er|im|ey|iş)\p{L}*|yarra[kğ]\p{L}*|piç\p{L}*|göt(veren|lek)?|amcık\p{L}*|kahpe\p{L}*|pezevenk\p{L}*|ibne\p{L}*)(?![\p{L}\p{N}])/giu;

export function clean(text: string) {
  return censor.applyTo(text, matcher.getAllMatches(text)).replace(TURKISH, '****');
}

export const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|io|xyz|ru|gg|me|co|app|link|ly)\b)/i;

// Collapse invisible characters and runs of whitespace, so padding cannot dodge the duplicate check.
export const tidy = (s: string) => s.normalize('NFKC').replace(/[​-‍﻿]/g, '').replace(/\s+/g, ' ').trim();

export const ipHash = (req: Request) => {
  const ip = req.headers.get('x-real-ip') ?? req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
  return createHash('sha256').update(`${process.env.JEVCRAFT_KEY}:${ip}`).digest('hex').slice(0, 32);
};
