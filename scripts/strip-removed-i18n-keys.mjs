// One-off cleanup: remove keys from every locale dict that no longer exist in
// en.ts (the source of truth). The i18n parity test requires each locale to
// have EXACTLY the en key set — no missing, no extras.
//
// This is a line-based filter: it never parses or reformats the files, so it
// is safe for every locale regardless of string escaping, multi-line values,
// or odd whitespace. Only lines that match the canonical entry shape
// `  'key': 'value',` (or a bare `  'key':`) for a REMOVED key are dropped;
// everything else is preserved byte-for-byte.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const I18N_DIR = join(import.meta.dirname, '..', 'src', 'lib', 'i18n');

// Extract the key from a dict entry line. en.ts uses unquoted keys
// (`  all_downloads: '...'`) while the locale files use quoted keys
// (`  'all_downloads': '...'`), so accept both. Returns null when the line is
// not an entry (header, footer, continuation, comment, blank).
function entryKey(line) {
  const m = /^ {2}'?([a-zA-Z0-9_]+)'?:/.exec(line);
  return m ? m[1] : null;
}

function loadKeys(filePath) {
  const keys = new Set();
  for (const line of readFileSync(filePath, 'utf8').split('\n')) {
    const k = entryKey(line);
    if (k) keys.add(k);
  }
  return keys;
}

const enKeys = loadKeys(join(I18N_DIR, 'en.ts'));

const files = readdirSync(I18N_DIR).filter(
  (f) => f.endsWith('.ts') && !['translations.ts', 'languageMetadata.ts'].includes(f),
);
let updated = 0;
let totalRemoved = 0;
for (const file of files) {
  const filePath = join(I18N_DIR, file);
  const text = readFileSync(filePath, 'utf8');
  const lines = text.split('\n');
  const kept = [];
  let removedHere = 0;
  for (const line of lines) {
    const k = entryKey(line);
    if (k !== null && !enKeys.has(k)) {
      removedHere += 1;
      continue;
    }
    kept.push(line);
  }
  if (removedHere === 0) continue;
  totalRemoved += removedHere;
  writeFileSync(filePath, kept.join('\n'), 'utf8');
  updated += 1;
}
console.log(`Stripped ${totalRemoved} orphaned keys from ${updated} locale files`);
