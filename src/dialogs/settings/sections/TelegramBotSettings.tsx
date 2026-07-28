/* src/dialogs/settings/sections/TelegramBotSettings.tsx */
import React, { useState, useCallback } from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Switch, TextField } from '../../../components/primitives';
import { Bot, Send, MessageSquare, Terminal } from 'lucide-react';
import { novaClient } from '../../../api/novaClient';

import { extractErrorMessage } from '../../../utils/formatUtils';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
  onAddToast: (type: 'success' | 'error' | 'warning' | 'info', title: string, msg: string) => void;
}

const BOT_COMMANDS = [
  { cmd: '/start', desc: 'Start the bot' },
  { cmd: '/help', desc: 'Show help message' },
  { cmd: '/list', desc: 'List active downloads' },
  { cmd: '/add', desc: 'Add a new download' },
  { cmd: '/pause', desc: 'Pause a download' },
  { cmd: '/resume', desc: 'Resume a download' },
  { cmd: '/delete', desc: 'Delete a download' },
];

export const TelegramBotSettings: React.FC<Props> = ({ settings, updateSetting, onAddToast }) => {
  const [testing, setTesting] = useState(false);

  const isConfigured = Boolean(settings.extra.tgBotToken && settings.extra.tgChatId);

  const handleTestConnection = useCallback(async () => {
    setTesting(true);
    try {
      const result = await novaClient.testTelegram();
      if (result.ok) {
        onAddToast('success', 'Telegram Test', 'Bot connection successful! Check your Telegram for a test message.');
      } else {
        onAddToast('error', 'Telegram Test', result.error || 'Test connection failed.');
      }
    } catch (error) {
      onAddToast('error', 'Telegram Test', extractErrorMessage(error, 'Failed to reach the daemon.'));
    } finally {
      setTesting(false);
    }
  }, [onAddToast]);

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* ── Bot Configuration ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Bot className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-sm font-extrabold text-[var(--info)]">Bot Configuration</h3>
          {isConfigured && (
            <span className="ml-auto px-2 py-0.5 bg-[var(--success-bg)] border border-[var(--success-border)] text-[var(--success)] rounded text-[10px] font-bold">
              Configured
            </span>
          )}
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <div className="flex items-center justify-between py-2">
            <span className="text-xs font-bold text-[var(--text-primary)]">Enable Telegram Bot</span>
            <Switch
              checked={settings.extra.tgEnabled}
              onChange={(v) => { updateSetting('extra', 'tgEnabled', v); }}
            />
          </div>

          {settings.extra.tgEnabled && (
            <div className="space-y-3 pt-2 border-t border-[var(--border-color)]/50 animate-in slide-in-from-top-2 duration-150">
              <TextField
                label="Bot Token"
                value={settings.extra.tgBotToken}
                onChange={(e) => { updateSetting('extra', 'tgBotToken', e.target.value); }}
                placeholder="123456:ABC-DEF..."
                type="password"
                style={{ direction: 'ltr', textAlign: 'left' }}
              />
              <TextField
                label="Chat ID"
                value={settings.extra.tgChatId}
                onChange={(e) => { updateSetting('extra', 'tgChatId', e.target.value); }}
                placeholder="e.g. 123456789"
                style={{ direction: 'ltr', textAlign: 'left' }}
              />
              <TextField
                label="API Base URL"
                value={settings.extra.tgApiBase}
                onChange={(e) => { updateSetting('extra', 'tgApiBase', e.target.value); }}
                placeholder="https://api.telegram.org"
                style={{ direction: 'ltr', textAlign: 'left' }}
              />
              <TextField
                label="File Upload Limit (MB)"
                value={String(settings.extra.tgFileUploadLimitMb)}
                onChange={(e) => { updateSetting('extra', 'tgFileUploadLimitMb', Number(e.target.value) || 50); }}
                placeholder="50"
                style={{ direction: 'ltr', textAlign: 'left' }}
              />
            </div>
          )}
        </div>
      </div>

      {/* ── Event Notifications ── */}
      {settings.extra.tgEnabled && (
        <div className="space-y-4">
          <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
            <MessageSquare className="w-4 h-4 text-[var(--warning)]" />
            <h3 className="text-sm font-extrabold text-[var(--warning)]">Event Notifications</h3>
          </div>

          <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
            <div className="flex items-center justify-between py-2">
              <span className="text-xs font-bold text-[var(--text-primary)]">Download Started</span>
              <Switch
                checked={settings.extra.tgEventStarted}
                onChange={(v) => { updateSetting('extra', 'tgEventStarted', v); }}
              />
            </div>
            <div className="flex items-center justify-between py-2">
              <span className="text-xs font-bold text-[var(--text-primary)]">Download Completed</span>
              <Switch
                checked={settings.extra.tgEventCompleted}
                onChange={(v) => { updateSetting('extra', 'tgEventCompleted', v); }}
              />
            </div>
            <div className="flex items-center justify-between py-2">
              <span className="text-xs font-bold text-[var(--text-primary)]">Download Failed</span>
              <Switch
                checked={settings.extra.tgEventFailed}
                onChange={(v) => { updateSetting('extra', 'tgEventFailed', v); }}
              />
            </div>
            <div className="flex items-center justify-between py-2">
              <span className="text-xs font-bold text-[var(--text-primary)]">Queue Completed</span>
              <Switch
                checked={settings.extra.tgEventQueueCompleted}
                onChange={(v) => { updateSetting('extra', 'tgEventQueueCompleted', v); }}
              />
            </div>
          </div>
        </div>
      )}

      {/* ── Full Control & Commands ── */}
      {settings.extra.tgEnabled && (
        <div className="space-y-4">
          <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
            <Terminal className="w-4 h-4 text-[var(--accent-primary)]" />
            <h3 className="text-sm font-extrabold text-[var(--accent-primary)]">Bot Control</h3>
          </div>

          <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
            <div className="flex items-center justify-between py-2">
              <div className="space-y-0.5">
                <span className="text-xs font-bold text-[var(--text-primary)]">Full Bot Control</span>
                <p className="text-[10px] text-[var(--text-muted)]">
                  Allows managing downloads via bot commands in Telegram.
                </p>
              </div>
              <Switch
                checked={settings.extra.tgFullControl}
                onChange={(v) => { updateSetting('extra', 'tgFullControl', v); }}
              />
            </div>

            <div className="space-y-1.5 pt-2 border-t border-[var(--border-color)]/50">
              <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide">
                Available Commands
              </span>
              <div className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded-lg overflow-hidden">
                {BOT_COMMANDS.map((cmd) => (
                  <div
                    key={cmd.cmd}
                    className="flex items-center gap-3 px-3 py-1.5 border-b border-[var(--border-color)]/30 last:border-b-0"
                  >
                    <code className="text-[11px] font-mono font-bold text-[var(--accent-primary)] w-[70px]">
                      {cmd.cmd}
                    </code>
                    <span className="text-[10px] text-[var(--text-muted)]">{cmd.desc}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Test Connection ── */}
      {settings.extra.tgEnabled && (
        <div className="space-y-4">
          <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => { void handleTestConnection(); }}
                disabled={testing || !isConfigured}
                className="px-3 py-1.5 bg-[var(--info-bg)] border border-[var(--info-border)] text-[var(--info)] rounded text-xs font-bold hover:bg-[var(--info-bg)] transition-all cursor-pointer flex items-center gap-1 disabled:opacity-50"
              >
                {testing && <Send className="w-3.5 h-3.5 animate-pulse" />}
                {testing ? 'Sending...' : 'Test Connection'}
              </button>
              {!isConfigured && (
                <span className="text-[10px] text-[var(--text-muted)]">
                  Set Bot Token and Chat ID first.
                </span>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
