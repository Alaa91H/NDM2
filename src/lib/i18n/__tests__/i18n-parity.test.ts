import { describe, it, expect } from 'vitest';
import { en } from '../en';
import { loadLanguage, getTranslation, isLanguageLoaded } from '../translations';

// Every locale file is a named export of a Record<string, string>.
const localeModules = import.meta.glob('../*.ts', { eager: true });

// The lazy loader picks the first object found in the module — matching what
// loadLanguage() does. Files export e.g. `export const en = {...}`.
function dictOf(module: unknown): Record<string, string> {
  if (!module || typeof module !== 'object') return {};
  const dict = Object.values(module).find(
    (value) => value && typeof value === 'object',
  );
  return (dict as Record<string, string>) ?? {};
}

describe('i18n key parity (REPAIR 0.2)', () => {
  const enKeys = Object.keys(en).sort();

  it('English dictionary is non-empty', () => {
    expect(enKeys.length).toBeGreaterThan(100);
  });

  const localeNames = Object.keys(localeModules).filter((path) => {
    const base = path.split('/').pop()!;
    return (
      base !== 'en.ts' &&
      base !== 'translations.ts' &&
      base !== 'languageMetadata.ts'
    );
  });

  it('covers every language listed in the loader', async () => {
    // translations.ts declares 132 languages; ensure the test sees them all.
    expect(localeNames.length).toBeGreaterThanOrEqual(130);
  });

  for (const path of localeNames) {
    const base = path.split('/').pop()!;
    const lang = base.replace(/\.ts$/, '');

    it(`${lang} has exactly the en keys`, async () => {
      const module = localeModules[path];
      const dict = dictOf(module);

      const dictKeys = Object.keys(dict).sort();
      const missing = enKeys.filter((k) => !(k in dict));
      const extra = dictKeys.filter((k) => !(k in en));

      expect(missing, `${lang} missing keys: ${missing.join(', ')}`).toEqual([]);
      expect(extra, `${lang} extra keys: ${extra.join(', ')}`).toEqual([]);
    });
  }

  it('every loader language actually resolves through loadLanguage', async () => {
    for (const path of localeNames) {
      const base = path.split('/').pop()!;
      const lang = base.replace(/\.ts$/, '');
      await loadLanguage(lang);
      expect(isLanguageLoaded(lang)).toBe(true);
      // A real key must return a translated string, not the key itself.
      const sample = enKeys[0];
      expect(typeof getTranslation(lang, sample)).toBe('string');
      expect(getTranslation(lang, sample).length).toBeGreaterThan(0);
    }
  });
});
