/* src/dialogs/settings/sections/LoggingSettings.tsx */
import React, { useState, useRef, useEffect, useCallback } from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { FormRow, Switch } from '../../../components/primitives';
import { ScrollText, Download, FileText, RefreshCw } from 'lucide-react';
import {
  logger,
  formatLogTimestamp,
  levelColor,
  levelBadgeBg,
  downloadAsFile,
  exportLogsAsJson,
  exportLogsAsText,
  type LogLevel,
} from '../../../utils/logger';
import { useI18n } from '../../../store/selectors';
import { tauriClient } from '../../../api/tauriClient';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
  onAddToast: (type: 'success' | 'error' | 'info' | 'warning', title: string, msg: string) => void;
}

export const LoggingSettings: React.FC<Props> = ({
  settings,
  updateSetting,
  onAddToast,
}) => {
  const t = useI18n();
  const [logs, setLogs] = useState(() => logger.getBufferSlice(undefined, undefined, 300));
  const [filterLevel, setFilterLevel] = useState<LogLevel | ''>('');
  const [filterSource, setFilterSource] = useState('');
  const [searchText, setSearchText] = useState('');
  const [autoScroll, setAutoScroll] = useState(true);
  const [expandedMessages, setExpandedMessages] = useState<Set<number>>(new Set());
  const scrollRef = useRef<HTMLDivElement>(null);

  const refreshLogs = useCallback(() => {
    const filtered = logger.getBufferSlice(
      filterLevel || undefined,
      filterSource || undefined,
      500,
    );
    setLogs(filtered);
  }, [filterLevel, filterSource]);

  useEffect(() => {
    const interval = setInterval(refreshLogs, 1000);
    return () => {
      clearInterval(interval);
    };
  }, [refreshLogs]);

  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  useEffect(() => {
    const loggingEnabled = settings.advanced.loggingEnabled;
    logger.setEnabled(loggingEnabled);
    const logLevel = settings.advanced.logLevel;
    logger.setMinLevel(logLevel);
  }, [settings.advanced.loggingEnabled, settings.advanced.logLevel]);

  const filteredLogs = searchText
    ? logs.filter((e) => e.message.toLowerCase().includes(searchText.toLowerCase()))
    : logs;

  const toggleExpand = (idx: number) => {
    setExpandedMessages((prev) => {
      const next = new Set(prev);
      if (next.has(idx)) {
        next.delete(idx);
      } else {
        next.add(idx);
      }
      return next;
    });
  };

  // Save the log content through the native save dialog (defaulting to the
  // desktop), writing via the Rust command when running inside Tauri, and
  // falling back to a browser download in dev/browser mode.
  const saveLogFile = async (
    content: string,
    filename: string,
    mimeType: string,
    filters: Array<{ name: string; extensions: string[] }>,
  ) => {
    try {
      const desktopDir = await tauriClient.getDesktopDir();
      if (desktopDir) {
        const sep = desktopDir.includes('\\') ? '\\' : '/';
        const chosen = await tauriClient.showSaveFilePicker(`${desktopDir}${sep}${filename}`, filters);
        if (!chosen) return;
        const ok = await tauriClient.saveTextFile(chosen, content);
        if (ok) {
          onAddToast('success', t('settings_logging_saved_title'), t('settings_logging_saved_msg'));
        } else {
          onAddToast('error', t('settings_logging_save_error'), t('settings_logging_save_error_msg'));
        }
        return;
      }
    } catch {
      /* fall through to browser download */
    }
    downloadAsFile(content, filename, mimeType);
    onAddToast('success', t('settings_logging_saved_title'), t('settings_logging_saved_msg'));
  };

  const handleExportLogs = () => {
    const data = logger.getBufferSlice(filterLevel || undefined, filterSource || undefined, 5000);
    const content = exportLogsAsJson(data, { level: filterLevel || 'all', source: filterSource || 'all' });
    const filename = `nova_logs_${new Date().toISOString().slice(0, 19).replace(/[T:]/g, '-')}.json`;
    void saveLogFile(content, filename, 'application/json', [{ name: 'JSON', extensions: ['json'] }]);
  };

  const handleExportTextLogs = () => {
    const data = logger.getBufferSlice(filterLevel || undefined, filterSource || undefined, 5000);
    const content = exportLogsAsText(data, { level: filterLevel || 'all', source: filterSource || 'all' });
    const filename = `nova_logs_${new Date().toISOString().slice(0, 19).replace(/[T:]/g, '-')}.txt`;
    void saveLogFile(content, filename, 'text/plain', [{ name: 'Text', extensions: ['txt'] }]);
  };

  const TRUNCATE_LENGTH = 120;

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      <div className="space-y-3 animate-in fade-in duration-150">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <ScrollText className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-xs font-extrabold text-[var(--info)]">{t('settings_logging_title')}</h3>
        </div>

        <FormRow label={t('settings_logging_enable')}>
          <Switch
            checked={settings.advanced.loggingEnabled}
            onChange={(v) => {
              updateSetting('advanced', 'loggingEnabled', v);
              logger.setEnabled(v);
            }}
          />
        </FormRow>

        <p className="text-[10px] text-[var(--text-muted)] leading-relaxed -mt-1">
          {t('settings_logging_desc')}
        </p>

        {settings.advanced.loggingEnabled && (
          <div className="space-y-2 animate-in fade-in duration-150">
            <div className="flex items-center gap-2 flex-wrap">
              <select
                value={filterLevel}
                onChange={(e) => {
                  setFilterLevel(e.target.value as LogLevel | '');
                }}
                className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1 text-[10px] font-bold text-[var(--text-primary)] cursor-pointer"
              >
                <option value="">{t('settings_logging_all_levels')}</option>
                <option value="debug">Debug</option>
                <option value="info">Info</option>
                <option value="warn">Warn</option>
                <option value="error">Error</option>
              </select>
              <input
                value={filterSource}
                onChange={(e) => {
                  setFilterSource(e.target.value);
                }}
                placeholder={t('settings_logging_filter_source')}
                className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1 text-[10px] font-mono text-[var(--text-primary)] placeholder:text-[var(--text-muted)] w-32"
                style={{ direction: 'ltr' }}
              />
              <input
                value={searchText}
                onChange={(e) => {
                  setSearchText(e.target.value);
                }}
                placeholder="Search logs..."
                className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1 text-[10px] font-mono text-[var(--text-primary)] placeholder:text-[var(--text-muted)] w-36"
                style={{ direction: 'ltr' }}
              />
              <button
                type="button"
                onClick={() => {
                  logger.clearBuffer();
                  setLogs([]);
                }}
                className="px-2 py-1 text-[10px] font-bold text-[var(--danger)] bg-[var(--danger-bg)] border border-[var(--danger-border)] rounded hover:opacity-80 cursor-pointer"
              >
                {t('settings_logging_clear')}
              </button>
              <button
                type="button"
                onClick={refreshLogs}
                className="px-2 py-1 text-[10px] font-bold text-[var(--text-secondary)] bg-[var(--bg-hover)] border border-[var(--border-color)] rounded hover:opacity-80 cursor-pointer flex items-center gap-1"
              >
                <RefreshCw className="w-3 h-3" />
                {t('settings_logging_refresh')}
              </button>
              <label className="flex items-center gap-1 text-[10px] text-[var(--text-muted)] font-bold cursor-pointer ml-auto">
                <input
                  type="checkbox"
                  checked={autoScroll}
                  onChange={(e) => {
                    setAutoScroll(e.target.checked);
                  }}
                  className="accent-[var(--accent-primary)]"
                />
                {t('settings_logging_autoscroll')}
              </label>
            </div>

            <div className="flex items-center gap-2 flex-wrap">
              <button
                type="button"
                onClick={handleExportLogs}
                className="px-2 py-1 text-[10px] font-bold text-[var(--info)] bg-[var(--info)]/10 border border-[var(--info)]/30 rounded hover:opacity-80 cursor-pointer flex items-center gap-1"
              >
                <Download className="w-3 h-3" />
                Export JSON
              </button>
              <button
                type="button"
                onClick={handleExportTextLogs}
                className="px-2 py-1 text-[10px] font-bold text-[var(--info)] bg-[var(--info)]/10 border border-[var(--info)]/30 rounded hover:opacity-80 cursor-pointer flex items-center gap-1"
              >
                <FileText className="w-3 h-3" />
                Save as TXT
              </button>
            </div>

            <div className="flex items-center gap-2 text-[10px] text-[var(--text-muted)] font-bold">
              <span>{filteredLogs.length} entries</span>
              <span className="text-[var(--border-color)]">|</span>
              <span>{t('settings_logging_buffer')}: 2000 max</span>
            </div>

            <div
              ref={scrollRef}
              className="bg-[var(--bg-input)] border border-[var(--border-color)] rounded-lg overflow-auto font-mono text-[10px] leading-tight"
              style={{ height: '320px' }}
            >
              {filteredLogs.length === 0 && (
                <div className="p-4 text-center text-[var(--text-muted)] italic">
                  {t('settings_logging_empty')}
                </div>
              )}
              {filteredLogs.map((entry, idx) => {
                const isExpanded = expandedMessages.has(idx);
                const needsTruncation = entry.message.length > TRUNCATE_LENGTH;
                const displayMessage = needsTruncation && !isExpanded
                  ? entry.message.slice(0, TRUNCATE_LENGTH) + '...'
                  : entry.message;

                return (
                  <div
                    key={`${String(entry.timestamp)}-${String(idx)}`}
                    className={`px-2 py-0.5 hover:bg-[var(--bg-hover)] border-b border-[var(--border-color)]/30 flex gap-2 ${needsTruncation ? 'cursor-pointer' : ''}`}
                    onClick={() => {
                      if (needsTruncation) toggleExpand(idx);
                    }}
                  >
                    <span className="text-[var(--text-muted)] shrink-0 w-[85px]">
                      {formatLogTimestamp(entry.timestamp)}
                    </span>
                    <span
                      className={`shrink-0 w-[40px] font-bold uppercase ${levelColor(entry.level)} border rounded px-1 text-center ${levelBadgeBg(entry.level)}`}
                    >
                      {entry.level}
                    </span>
                    <span className="text-[var(--accent-primary)] shrink-0 w-[120px] truncate">{entry.source}</span>
                    <span className="text-[var(--text-primary)] flex-1 min-w-0 break-all">{displayMessage}</span>
                    {needsTruncation && (
                      <span className="text-[var(--text-muted)] shrink-0 text-[9px] self-center">
                        {isExpanded ? '[-]' : '[+]'}
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
