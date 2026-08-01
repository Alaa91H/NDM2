#!/usr/bin/env node
/**
 * Repair U+FFFD mojibake in browser-extension locale files.
 *
 * The corruption pattern is uniform: a UTF-8 multi-byte char lost its high
 * bytes and collapsed to U+FFFD followed by a surviving ASCII char. The
 * surviving char (plus language context) reveals the original letter:
 *   de:  Grö�Ye -> Größe      (�Y = ß),  �-ffnen -> Öffnen (�- = Ö)
 *   ro:  Român�f -> Română    (�f = ă),  fi�Tier -> fișier (�T = ș)
 *   tr:  ba�Ylantı -> bağlantı (�Y = ğ/ş by context)
 *   sv:  �-ppna -> Öppna      (�- = Ö),  mer�?� -> mer…    (�?� = …)
 *
 * Latin-script locales are repaired with a per-language mapping table.
 * Non-Latin scripts (bn, fa, th) collapsed beyond recovery and must be
 * re-translated — this tool refuses to touch them.
 */
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const LOCALE_DIR = 'src/i18n/locales';

// Per-language replacement maps. Keys are the literal corrupted sequence
// (U+FFFD + following chars), values the correct string. Longer keys FIRST
// so e.g. `�?�` (…) wins over `�?t` (Ét) — ordering matters.
const MAPS = {
  // German: ß, Ö, Ü, …, —
  de: {
    '…\uFFFD': '…', // leftover after �?� -> …
    '\uFFFDY': 'ß',
    '\uFFFD?': '…',
    '\uFFFD-ffnen': 'Öffnen',
    '\uFFFDobergabe': 'Übergabe',
    '\uFFFDober': 'Über',
    '\uFFFD"': '—',
  },
  // Swedish: Ö, Å, …
  sv: {
    '…\uFFFD': '…',
    '\uFFFD-': 'Ö',
    '\uFFFD.': 'Å', // �.teransluter -> Återansluter
    '\uFFFD?': '…',
  },
  // Romanian: ă, ș, ț, Î, Ș, …
  ro: {
    '…\uFFFD': '…',
    '\uFFFDZn': 'În', // �Zncă -> Încă
    '\uFFFD~': 'Ș', // �~tergeși -> Ștergeși
    '\uFFFDf': 'ă',
    '\uFFFDc': 'ț', // pun�>e -> punțe
    '\uFFFD>': 'ș',
    '\uFFFDT': 'ș', // fi�Tier -> fișier
    '\uFFFDF': 'Ă',
    '\uFFFD?': '…',
  },
  // Turkish: ğ, ş, …, ö, ı, Ş
  tr: {
    '…\uFFFD': '…',
    '\uFFFD-': 'Ö', // �-lü -> Ölü
    '\uFFFDz': 'Şi', // �zifreli -> Şifreli
    '\uFFFDe': 'Ş',
    '\uFFFDY': 'ğ',
    '\uFFFD?': '…',
    '\uFFFDo': 'ş',
    '\uFFFD"': 'ö',
    '\uFFFD>': 'ş',
    '\uFFFDi': 'ı',
  },
  // Spanish: …, ú
  es: {
    '…\uFFFD': '…',
    '\uFFFDs': 'ús', // �sltima -> última, �stil -> útil
    '\uFFFD?': '…',
  },
  // French: …, É/é/œ
  fr: {
    '…\uFFFD': '…',
    '\uFFFD?t': 'Ét',
    '\uFFFD?c': 'Éc',
    '\uFFFD?': '…',
    '\uFFFDe': 'é',
    '\uFFFDc': 'œ',
  },
  // Italian: …, —
  it: {
    '…\uFFFD': '…',
    '\uFFFD?': '…',
    '\uFFFD"': '—',
  },
  // Dutch: …, —
  nl: {
    '…\uFFFD': '…',
    '\uFFFD?': '…',
    '\uFFFD"': '—',
  },
  // Portuguese: …, ú, ã/õ/ç
  pt: {
    '…\uFFFD': '…',
    '\uFFFDs': 'ús', // �sltima -> última, �stil -> útil
    '\uFFFD?': '…',
    '\uFFFDa': 'ã',
    '\uFFFDo': 'õ',
    '\uFFFDc': 'ç',
  },
  // Indonesian: …
  id: {
    '…\uFFFD': '…',
    '\uFFFD?': '…',
  },
};

// Locales that collapsed beyond recovery (script lost) — need re-translation.
const NON_LATIN = new Set(['bn', 'fa', 'th']);

function countFffd(text) {
  return (text.match(/\uFFFD/g) || []).length;
}

function repairFile(lang, file) {
  const path = join(LOCALE_DIR, file);
  const original = readFileSync(path, 'utf8');
  const map = MAPS[lang];
  if (!map) {
    console.warn(`[fix-locale] ${file}: no mapping for language "${lang}" — skipped`);
    return;
  }
  let repaired = original;
  for (const [from, to] of Object.entries(map)) {
    repaired = repaired.split(from).join(to);
  }
  const before = countFffd(original);
  const after = countFffd(repaired);
  writeFileSync(path, repaired, 'utf8');
  console.log(
    `[fix-locale] ${file}: U+FFFD ${before} -> ${after}${after === 0 ? ' ✅' : ' ⚠️  remaining'}`,
  );
}

function main() {
  if (!existsSync(LOCALE_DIR)) {
    console.error(`[fix-locale] missing ${LOCALE_DIR}`);
    process.exit(1);
  }
  const files = readdirSync(LOCALE_DIR).filter((f) => f.endsWith('.ts'));
  let fixed = 0;
  let remaining = 0;
  for (const file of files) {
    const lang = file.replace(/\.ts$/, '');
    if (NON_LATIN.has(lang)) {
      const body = readFileSync(join(LOCALE_DIR, file), 'utf8');
      const n = countFffd(body);
      if (n > 0) {
        console.warn(`[fix-locale] ${file}: non-Latin script, ${n} U+FFFD — requires re-translation`);
        remaining += n;
      }
      continue;
    }
    const before = countFffd(readFileSync(join(LOCALE_DIR, file), 'utf8'));
    if (before === 0) continue;
    repairFile(lang, file);
    fixed += 1;
  }
  console.log(`[fix-locale] fixed ${fixed} files; ${remaining} U+FFFD remain in non-Latin locales.`);
  if (remaining > 0) {
    console.error('[fix-locale] non-Latin locales (bn, fa, th) still need manual re-translation.');
  }
}

main();
