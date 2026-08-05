/* src/dialogs/settings/sections/BrowserSettings.tsx */
import React from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Switch, SelectField } from '../../../components/primitives';
import { Globe, Keyboard } from 'lucide-react';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
}

export const BrowserSettings: React.FC<Props> = ({ settings, updateSetting }) => {
  const browsers: Array<{ key: 'chrome' | 'edge' | 'firefox' | 'safari'; label: string }> = [
    { key: 'chrome', label: 'Google Chrome' },
    { key: 'edge', label: 'Microsoft Edge' },
    { key: 'firefox', label: 'Mozilla Firefox' },
    { key: 'safari', label: 'Safari' },
  ];

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* ── Browser Integration ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Globe className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-sm font-extrabold text-[var(--info)]">Browser Integration</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          {browsers.map((browser) => (
            <div key={browser.key} className="flex items-center justify-between py-2">
              <span className="text-xs font-bold text-[var(--text-primary)]">{browser.label}</span>
              <Switch
                checked={settings.general.integrateWithBrowsers[browser.key]}
                onChange={(v) => {
                  updateSetting('general', 'integrateWithBrowsers', {
                    ...settings.general.integrateWithBrowsers,
                    [browser.key]: v,
                  });
                }}
              />
            </div>
          ))}
        </div>
      </div>

      {/* ── Monitoring ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Keyboard className="w-4 h-4 text-[var(--warning)]" />
          <h3 className="text-sm font-extrabold text-[var(--warning)]">Monitoring</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Clipboard Monitoring</span>
            <Switch
              checked={settings.general.monitorClipboard}
              onChange={(v) => {
                updateSetting('general', 'monitorClipboard', v);
              }}
            />
          </div>
        </div>
      </div>

      {/* ── Intercept Keys ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Keyboard className="w-4 h-4 text-[var(--accent-primary)]" />
          <h3 className="text-sm font-extrabold text-[var(--accent-primary)]">Intercept Keys</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <SelectField
            label="Browser Intercept Modifier Keys"
            value={settings.advanced.browserInterceptKeys}
            onChange={(e) => {
              updateSetting('advanced', 'browserInterceptKeys', e.target.value);
            }}
            options={[
              { value: 'Alt', label: 'Alt' },
              { value: 'Ctrl', label: 'Ctrl' },
              { value: 'Shift', label: 'Shift' },
              { value: 'Alt+Ctrl', label: 'Alt + Ctrl' },
            ]}
          />
          <p className="text-[10px] text-[var(--text-muted)] leading-relaxed">
            Modifier key to hold while clicking a link to send it to NOVA instead of opening in the browser.
          </p>
        </div>
      </div>
    </div>
  );
};
