/* src/dialogs/settings/sections/IntegrationsSettings.tsx */
import React from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Switch, TextField } from '../../../components/primitives';
import { Webhook, Mail } from 'lucide-react';


interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
}

export const IntegrationsSettings: React.FC<Props> = ({ settings, updateSetting }) => {
  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* ── Webhooks ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Webhook className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-sm font-extrabold text-[var(--info)]">Webhooks</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Enable Webhook</span>
            <Switch
              checked={settings.extra.webhookActive}
              onChange={(v) => { updateSetting('extra', 'webhookActive', v); }}
            />
          </div>
          <TextField
            label="Webhook URL"
            value={settings.extra.webhookUrl}
            onChange={(e) => { updateSetting('extra', 'webhookUrl', e.target.value); }}
            placeholder="https://example.com/webhook"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
          <TextField
            label="Auth Token"
            value={settings.extra.webhookAuth}
            onChange={(e) => { updateSetting('extra', 'webhookAuth', e.target.value); }}
            placeholder="Optional bearer token"
            type="password"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
        </div>
      </div>

      {/* ── SMTP ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Mail className="w-4 h-4 text-[var(--success)]" />
          <h3 className="text-sm font-extrabold text-[var(--success)]">SMTP Email</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Enable SMTP</span>
            <Switch
              checked={settings.extra.smtpActive}
              onChange={(v) => { updateSetting('extra', 'smtpActive', v); }}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <TextField
              label="SMTP Host"
              value={settings.extra.smtpHost}
              onChange={(e) => { updateSetting('extra', 'smtpHost', e.target.value); }}
              placeholder="smtp.gmail.com"
              style={{ direction: 'ltr', textAlign: 'left' }}
            />
            <TextField
              label="SMTP Port"
              value={settings.extra.smtpPort}
              onChange={(e) => { updateSetting('extra', 'smtpPort', e.target.value); }}
              placeholder="587"
              style={{ direction: 'ltr', textAlign: 'left' }}
            />
          </div>
          <TextField
            label="Username"
            value={settings.extra.smtpUser}
            onChange={(e) => { updateSetting('extra', 'smtpUser', e.target.value); }}
            placeholder="user@example.com"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
          <TextField
            label="Password"
            value={settings.extra.smtpPass}
            onChange={(e) => { updateSetting('extra', 'smtpPass', e.target.value); }}
            placeholder="App password"
            type="password"
            style={{ direction: 'ltr', textAlign: 'left' }}
          />
        </div>
      </div>
    </div>
  );
};
