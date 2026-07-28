/* src/dialogs/settings/sections/AdvancedSettings.tsx */
import React, { useState } from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { FormRow, Switch, TextField, SelectField } from '../../../components/primitives';
import { Terminal, Plus, Trash2 } from 'lucide-react';
import { useI18n } from '../../../store/selectors';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
}

export const AdvancedSettings: React.FC<Props> = ({
  settings,
  updateSetting,
}) => {
  const t = useI18n();
  const [headers, setHeaders] = useState<Array<{ key: string; value: string }>>([
    { key: 'X-NOVA-Client', value: 'desktop' },
  ]);
  const [headerKeyInput, setHeaderKeyInput] = useState('');
  const [headerValueInput, setHeaderValueInput] = useState('');

  const addHeader = () => {
    const k = headerKeyInput.trim();
    if (!k) return;
    setHeaders((prev) => [...prev, { key: k, value: headerValueInput.trim() }]);
    setHeaderKeyInput('');
    setHeaderValueInput('');
  };

  const removeHeader = (idx: number) => {
    setHeaders((prev) => prev.filter((_, i) => i !== idx));
  };

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* Service Configuration */}
      <div className="space-y-4 animate-in fade-in duration-150">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Terminal className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-xs font-extrabold text-[var(--info)]">{t('settings_advanced_ports')}</h3>
        </div>
        <div className="grid grid-cols-1 gap-3">
          <TextField
            label={t('settings_service_port')}
            value={settings.extra.daemonPort}
            onChange={(e) => {
              updateSetting('extra', 'daemonPort', e.target.value);
            }}
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
          <TextField
            label={t('settings_bind_address')}
            value={settings.extra.daemonBindAddress}
            onChange={(e) => {
              updateSetting('extra', 'daemonBindAddress', e.target.value);
            }}
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
        </div>
        <FormRow label={t('settings_experimental')}>
          <Switch
            checked={settings.extra.experimentalFeatures}
            onChange={(v) => {
              updateSetting('extra', 'experimentalFeatures', v);
            }}
          />
        </FormRow>
      </div>

      {/* Protocol Settings */}
      <div className="space-y-4 animate-in fade-in duration-150">
        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <span className="text-[11px] font-extrabold text-[var(--text-secondary)] block border-b border-[var(--border-color)]/50 pb-1 mb-1">
            {t('set_net_protocols_title')}
          </span>
          <SelectField
            label={t('settings_advanced_log_level')}
            value={settings.advanced.logLevel}
            onChange={(e) => {
              updateSetting('advanced', 'logLevel', e.target.value);
            }}
            options={[
              { value: 'info', label: t('settings_log_info') },
              { value: 'debug', label: t('settings_log_debug') },
              { value: 'error', label: t('settings_log_error') },
            ]}
          />
          <SelectField
            label={t('settings_browser_intercept_keys')}
            value={settings.advanced.browserInterceptKeys}
            onChange={(e) => {
              updateSetting('advanced', 'browserInterceptKeys', e.target.value);
            }}
            options={[
              { value: 'Alt', label: t('settings_intercept_alt') },
              { value: 'Ctrl', label: t('settings_intercept_ctrl') },
              { value: 'Shift', label: t('settings_intercept_shift') },
              { value: 'Alt+Ctrl', label: t('settings_intercept_alt_ctrl') },
            ]}
          />
          <FormRow label="Dynamic allocation">
            <Switch
              checked={settings.advanced.dynamicAllocation}
              onChange={(v) => {
                updateSetting('advanced', 'dynamicAllocation', v);
              }}
            />
          </FormRow>
          <TextField
            label="Buffer size (KB)"
            value={String(settings.advanced.bufferSizeKb)}
            onChange={(e) => {
              updateSetting('advanced', 'bufferSizeKb', Number(e.target.value) || 0);
            }}
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
        </div>
      </div>

      {/* Default Headers */}
      <div className="space-y-4 animate-in fade-in duration-150">
        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <span className="text-[11px] font-extrabold text-[var(--text-secondary)] block border-b border-[var(--border-color)]/50 pb-1 mb-1">
            {t('settings_default_headers')}
          </span>
          {headers.length === 0 && (
            <p className="text-[10px] text-[var(--text-muted)] italic">{t('settings_default_headers_empty')}</p>
          )}
          {headers.map((h, idx) => (
            <div key={`${h.key}-${String(idx)}`} className="grid grid-cols-[1fr_1fr_auto] gap-2 items-center">
              <span
                className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1.5 text-xs font-mono truncate text-[var(--text-primary)]"
                title={h.key}
              >
                {h.key}
              </span>
              <span
                className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1.5 text-xs font-mono truncate text-[var(--text-primary)]"
                title={h.value}
              >
                {h.value}
              </span>
              <button
                type="button"
                onClick={() => {
                  removeHeader(idx);
                }}
                className="p-1.5 rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger)] hover:bg-[var(--danger-bg)] transition-colors cursor-pointer shrink-0"
                title={t('settings_default_headers_remove')}
              >
                <Trash2 className="w-3 h-3" />
              </button>
            </div>
          ))}
          <div className="grid grid-cols-[1fr_1fr_auto] gap-2 items-center">
            <input
              value={headerKeyInput}
              onChange={(e) => {
                setHeaderKeyInput(e.target.value);
              }}
              placeholder={t('settings_header_key')}
              className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1.5 text-xs font-mono text-left focus:border-[var(--accent-primary)] focus:outline-none text-[var(--text-primary)] placeholder:text-[var(--text-muted)]"
              style={{ direction: 'ltr' }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') addHeader();
              }}
            />
            <input
              value={headerValueInput}
              onChange={(e) => {
                setHeaderValueInput(e.target.value);
              }}
              placeholder={t('settings_header_value')}
              className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1.5 text-xs font-mono text-left focus:border-[var(--accent-primary)] focus:outline-none text-[var(--text-primary)] placeholder:text-[var(--text-muted)]"
              style={{ direction: 'ltr' }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') addHeader();
              }}
            />
            <button
              type="button"
              onClick={addHeader}
              className="p-1.5 rounded border border-[var(--accent-border)] bg-[var(--accent-primary)]/10 text-[var(--accent-primary)] hover:bg-[var(--accent-primary)]/20 transition-colors cursor-pointer shrink-0"
              title={t('settings_default_headers_add')}
            >
              <Plus className="w-3 h-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
