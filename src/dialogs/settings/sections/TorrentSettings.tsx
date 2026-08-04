/* src/dialogs/settings/sections/TorrentSettings.tsx */
import React from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Switch, TextField } from '../../../components/primitives';
import { Magnet } from 'lucide-react';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
}

export const TorrentSettings: React.FC<Props> = ({ settings, updateSetting }) => {
  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Magnet className="w-4 h-4 text-[var(--warning)]" />
          <h3 className="text-sm font-extrabold text-[var(--warning)]">Torrent Settings</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Enable Torrent Downloads</span>
            <Switch
              checked={settings.extra.torrentEnabled}
              onChange={(v) => {
                updateSetting('extra', 'torrentEnabled', v);
              }}
            />
          </div>

          {settings.extra.torrentEnabled && (
            <div className="space-y-3 pt-2 border-t border-[var(--border-color)]/50 animate-in slide-in-from-top-2 duration-150">
              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--text-primary)]">Enable DHT</span>
                <Switch
                  checked={settings.extra.torrentDht}
                  onChange={(v) => {
                    updateSetting('extra', 'torrentDht', v);
                  }}
                />
              </div>
              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--text-primary)]">Enable PEX</span>
                <Switch
                  checked={settings.extra.torrentPex}
                  onChange={(v) => {
                    updateSetting('extra', 'torrentPex', v);
                  }}
                />
              </div>
              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--text-primary)]">Encrypt Transfers</span>
                <Switch
                  checked={settings.extra.torrentEncrypt}
                  onChange={(v) => {
                    updateSetting('extra', 'torrentEncrypt', v);
                  }}
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <TextField
                  label="Listening Port"
                  value={settings.extra.torrentPort}
                  onChange={(e) => {
                    updateSetting('extra', 'torrentPort', e.target.value);
                  }}
                  placeholder="Default: 6881"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
                <TextField
                  label="Max Peers"
                  value={settings.extra.torrentMaxPeers}
                  onChange={(e) => {
                    updateSetting('extra', 'torrentMaxPeers', e.target.value);
                  }}
                  placeholder="Default: 50"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
              </div>

              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--text-primary)]">Allow Seeding</span>
                <Switch
                  checked={settings.extra.torrentSeeding}
                  onChange={(v) => {
                    updateSetting('extra', 'torrentSeeding', v);
                  }}
                />
              </div>
              <div className="flex items-center justify-between py-2">
                <span className="text-xs font-bold text-[var(--text-primary)]">Stop on Battery</span>
                <Switch
                  checked={settings.extra.torrentBatteryStop}
                  onChange={(v) => {
                    updateSetting('extra', 'torrentBatteryStop', v);
                  }}
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <TextField
                  label="Ratio Limit"
                  value={settings.extra.torrentRatioLimit}
                  onChange={(e) => {
                    updateSetting('extra', 'torrentRatioLimit', e.target.value);
                  }}
                  placeholder="e.g. 1.0"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
                <TextField
                  label="Upload Speed (KB/s)"
                  value={settings.extra.torrentUploadSpeed}
                  onChange={(e) => {
                    updateSetting('extra', 'torrentUploadSpeed', e.target.value);
                  }}
                  placeholder="e.g. 100"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
              </div>
              <p className="text-[10px] text-[var(--text-muted)] leading-relaxed">
                Leave ratio and speed fields empty for unlimited.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
