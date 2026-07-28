/* src/dialogs/settings/sections/MediaSettings.tsx */
import React from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Switch, SelectField, TextField } from '../../../components/primitives';
import { Video, Subtitles, Film } from 'lucide-react';


interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
}

export const MediaSettings: React.FC<Props> = ({ settings, updateSetting }) => {
  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* ── Video Quality ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Video className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-sm font-extrabold text-[var(--info)]">Video Quality</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <SelectField
            label="Default Video Quality"
            value={settings.extra.videoQuality}
            onChange={(e) => { updateSetting('extra', 'videoQuality', e.target.value); }}
            options={[
              { value: 'best', label: 'Best Quality' },
              { value: 'good', label: 'Good (Balanced)' },
              { value: 'worst', label: 'Smallest File Size' },
            ]}
          />
        </div>
      </div>

      {/* ── Subtitles ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Subtitles className="w-4 h-4 text-[var(--success)]" />
          <h3 className="text-sm font-extrabold text-[var(--success)]">Subtitles</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Download Subtitles</span>
            <Switch
              checked={settings.extra.downloadSubtitles}
              onChange={(v) => { updateSetting('extra', 'downloadSubtitles', v); }}
            />
          </div>
          <TextField
            label="Subtitle Language"
            value={settings.extra.subtitleLanguage}
            onChange={(e) => { updateSetting('extra', 'subtitleLanguage', e.target.value); }}
            placeholder="e.g. en, es, fr (leave empty for all)"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
          <p className="text-[10px] text-[var(--text-muted)] leading-relaxed">
            Comma-separated language codes (ISO 639-1). Leave empty to download all available subtitles.
          </p>
        </div>
      </div>

      {/* ── FFmpeg ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Film className="w-4 h-4 text-[var(--warning)]" />
          <h3 className="text-sm font-extrabold text-[var(--warning)]">FFmpeg</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <TextField
            label="FFmpeg Path"
            value={settings.extra.ffmpegPath}
            onChange={(e) => { updateSetting('extra', 'ffmpegPath', e.target.value); }}
            placeholder="Leave empty to use bundled FFmpeg"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Auto-Merge Segments</span>
            <Switch
              checked={settings.extra.ffmpegAutoMerge}
              onChange={(v) => { updateSetting('extra', 'ffmpegAutoMerge', v); }}
            />
          </div>
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Delete Segments After Merge</span>
            <Switch
              checked={settings.extra.ffmpegDeleteSegments}
              onChange={(v) => { updateSetting('extra', 'ffmpegDeleteSegments', v); }}
            />
          </div>
          <p className="text-[10px] text-[var(--text-muted)] leading-relaxed">
            After merging, individual segment files are removed to save disk space.
          </p>
        </div>
      </div>
    </div>
  );
};
