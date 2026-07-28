/* src/dialogs/settings/sections/DiagnosticsStatus.tsx */
import React, { useState } from 'react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { FormRow, Switch } from '../../../components/primitives';
import {
  Activity,
  Cpu,
  Shield,
  Zap,
  Globe,
  RefreshCw,
} from 'lucide-react';
import { useBridgeData, useSettingsActions, useI18n } from '../../../store/selectors';
import { novaClient } from '../../../api/novaClient';
import { useEngineCapabilities } from '../../../capabilities/EngineCapabilityContext';
import { extractErrorMessage } from '../../../utils/formatUtils';

interface Props {
  settings: AppSettings;
  onAddToast: (type: 'success' | 'error' | 'info' | 'warning', title: string, msg: string) => void;
}

export const DiagnosticsStatus: React.FC<Props> = ({
  settings,
  onAddToast,
}) => {
  const t = useI18n();
  const bridge = useBridgeData();
  const { updateSettings } = useSettingsActions();
  const engineCapabilities = useEngineCapabilities();

  const [showCapDetails, setShowCapDetails] = useState(true);
  const [pinging, setPinging] = useState(false);
  const [pingLatency, setPingLatency] = useState<number | null>(null);

  const updateSetting = (section: keyof AppSettings, key: string, value: unknown) => {
    updateSettings({ ...settings, [section]: { ...settings[section], [key]: value } }, false);
  };

  const handleRunPing = async () => {
    setPinging(true);
    setPingLatency(null);
    const started = performance.now();
    try {
      const health = await novaClient.health();
      const latency = Math.max(1, Math.round(performance.now() - started));
      setPingLatency(latency);
      onAddToast(
        health.status === 'connected' ? 'success' : 'warning',
        t('settings_toast_ping'),
        `NOVA responded in ${String(latency)}ms with status: ${health.status}.`,
      );
    } catch (error) {
      onAddToast('error', t('settings_toast_ping_failed'), extractErrorMessage(error, t('settings_toast_no_response')));
    } finally {
      setPinging(false);
    }
  };

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* Section 1: Service Bridge Status */}
      <div className="space-y-4 animate-in fade-in duration-150">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Activity className="w-4 h-4 text-[var(--success)]" />
          <h3 className="text-xs font-extrabold text-[var(--success)]">{t('settings_service_bridge')}</h3>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
            <span className="text-[10px] text-[var(--text-muted)] block font-bold">
              {t('settings_bridge_service')}
            </span>
            <span className="text-xs font-mono text-[var(--success)]">{bridge.status}</span>
          </div>
          <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
            <span className="text-[10px] text-[var(--text-muted)] block font-bold">{t('settings_bridge_pid')}</span>
            <span className="text-xs font-mono">{bridge.pid || '-'}</span>
          </div>
          <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
            <span className="text-[10px] text-[var(--text-muted)] block font-bold">
              {t('settings_bridge_version')}
            </span>
            <span className="text-xs font-mono">{bridge.version || '-'}</span>
          </div>
          <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
            <span className="text-[10px] text-[var(--text-muted)] block font-bold">{t('settings_bridge_http')}</span>
            <span className="text-xs font-mono">127.0.0.1:{settings.extra.daemonPort || '3199'}</span>
          </div>
        </div>
        <FormRow label={t('settings_auto_reconnect')}>
          <Switch
            checked={settings.extra.autoReconnectDaemon}
            onChange={(v) => {
              updateSetting('extra', 'autoReconnectDaemon', v);
            }}
          />
        </FormRow>
        <FormRow label={t('settings_enable_sse')}>
          <Switch
            checked={settings.extra.enableSse}
            onChange={(v) => {
              updateSetting('extra', 'enableSse', v);
            }}
          />
        </FormRow>
        <button
          type="button"
          onClick={() => {
            void handleRunPing();
          }}
          disabled={pinging}
          className="px-3 py-1.5 bg-[var(--success-bg)] border border-[var(--success-border)] text-[var(--success)] rounded text-xs font-bold hover:bg-[var(--success-bg)] transition-all cursor-pointer flex items-center gap-1 disabled:opacity-50"
        >
          {pinging && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
          {t('settings_test_response')}
        </button>
        {pingLatency != null && (
          <p className="text-[11px] text-[var(--success)] font-mono">Response: {pingLatency}ms</p>
        )}
      </div>

      {/* Section 2: Engine Capabilities */}
      <div className="space-y-4 animate-in fade-in duration-150">
        <div className="border-t border-[var(--border-color)]/40 pt-3 mt-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Cpu className="w-4 h-4 text-cyan-500" />
              <h3 className="text-xs font-extrabold text-cyan-400">Engine Capabilities</h3>
            </div>
            <button
              type="button"
              onClick={() => {
                setShowCapDetails(!showCapDetails);
              }}
              className="text-[10px] text-[var(--text-muted)] hover:text-[var(--text-secondary)] transition-colors cursor-pointer"
            >
              {showCapDetails ? '? Collapse' : '? Expand'}
            </button>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mt-2">
            <div
              className={`border rounded-lg p-2 text-center ${engineCapabilities.directReady ? 'bg-[var(--success-bg)] border-[var(--success-border)]' : 'bg-[var(--danger-bg)] border-[var(--danger-border)]'}`}
            >
              <Zap
                className={`w-3.5 h-3.5 mx-auto mb-1 ${engineCapabilities.directReady ? 'text-[var(--success)]' : 'text-[var(--danger)]'}`}
              />
              <span className="text-[9px] font-bold text-[var(--text-secondary)] block">libcurl</span>
              <span
                className={`text-[10px] font-mono font-bold ${engineCapabilities.directReady ? 'text-[var(--success)]' : 'text-[var(--danger)]'}`}
              >
                {engineCapabilities.directReady ? 'Active' : 'Unavailable'}
              </span>
            </div>
            <div
              className={`border rounded-lg p-2 text-center ${engineCapabilities.mediaReady ? 'bg-[var(--success-bg)] border-[var(--success-border)]' : 'bg-[var(--warning-bg)] border-[var(--warning-border)]'}`}
            >
              <Globe
                className={`w-3.5 h-3.5 mx-auto mb-1 ${engineCapabilities.mediaReady ? 'text-[var(--success)]' : 'text-[var(--warning)]'}`}
              />
              <span className="text-[9px] font-bold text-[var(--text-secondary)] block">Media Engine</span>
              <span
                className={`text-[10px] font-mono font-bold ${engineCapabilities.mediaReady ? 'text-[var(--success)]' : 'text-[var(--warning)]'}`}
              >
                {engineCapabilities.mediaReady ? 'Active' : 'Unavailable'}
              </span>
            </div>
            <div
              className={`border rounded-lg p-2 text-center ${engineCapabilities.ffmpegReady ? 'bg-[var(--success-bg)] border-[var(--success-border)]' : 'bg-[var(--warning-bg)] border-[var(--warning-border)]'}`}
            >
              <Shield
                className={`w-3.5 h-3.5 mx-auto mb-1 ${engineCapabilities.ffmpegReady ? 'text-[var(--success)]' : 'text-[var(--warning)]'}`}
              />
              <span className="text-[9px] font-bold text-[var(--text-secondary)] block">FFmpeg</span>
              <span
                className={`text-[10px] font-mono font-bold ${engineCapabilities.ffmpegReady ? 'text-[var(--success)]' : 'text-[var(--warning)]'}`}
              >
                {engineCapabilities.ffmpegReady ? 'Active' : 'Unavailable'}
              </span>
            </div>
            <div className="border border-[var(--border-color)] rounded-lg p-2 text-center bg-[var(--bg-hover)]/30">
              <span className="text-[9px] font-bold text-[var(--text-secondary)] block">Direct Options</span>
              <span className="text-[10px] font-mono font-bold text-cyan-400">
                {engineCapabilities.directOptionKeys.size}
              </span>
            </div>
          </div>

          {showCapDetails && (
            <div className="mt-3 space-y-3 animate-in fade-in duration-150">
              {/* Protocols */}
              <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
                <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wider block mb-2">
                  Direct Protocols ({engineCapabilities.directProtocols.length})
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {engineCapabilities.directProtocols.sort().map((proto) => (
                    <span
                      key={proto}
                      className="px-1.5 py-0.5 bg-cyan-500/10 border border-cyan-500/20 text-cyan-400 text-[9px] font-mono font-bold rounded"
                    >
                      {proto}
                    </span>
                  ))}
                </div>
              </div>

              {/* Supported Options */}
              <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
                <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wider block mb-2">
                  Direct Option Keys ({engineCapabilities.directOptionKeys.size} supported,{' '}
                  {engineCapabilities.unsupportedDirectOptionKeys.size} unsupported)
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {Array.from(engineCapabilities.directOptionKeys)
                    .sort()
                    .map((key) => (
                      <span
                        key={key}
                        className="px-1.5 py-0.5 bg-[var(--success-bg)] border border-[var(--success-border)] text-[var(--success)] text-[8px] font-mono rounded"
                      >
                        {key}
                      </span>
                    ))}
                  {Array.from(engineCapabilities.unsupportedDirectOptionKeys)
                    .sort()
                    .map((key) => (
                      <span
                        key={key}
                        className="px-1.5 py-0.5 bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger)]/50 text-[8px] font-mono rounded line-through"
                      >
                        {key}
                      </span>
                    ))}
                </div>
              </div>

              {/* Media Options */}
              <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
                <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wider block mb-2">
                  Media Option Keys ({engineCapabilities.mediaOptionKeys.size} supported)
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {Array.from(engineCapabilities.mediaOptionKeys)
                    .sort()
                    .slice(0, 40)
                    .map((key) => (
                      <span
                        key={key}
                        className="px-1.5 py-0.5 bg-[var(--warning-bg)] border border-[var(--warning-border)] text-[var(--warning)] text-[8px] font-mono rounded"
                      >
                        {key}
                      </span>
                    ))}
                  {engineCapabilities.mediaOptionKeys.size > 40 && (
                    <span className="px-1.5 py-0.5 bg-[var(--bg-hover)] text-[var(--text-muted)] text-[8px] font-mono rounded">
                      +{engineCapabilities.mediaOptionKeys.size - 40} more
                    </span>
                  )}
                </div>
              </div>

              {/* Routing */}
              <div className="bg-[var(--bg-hover)]/30 border border-[var(--border-color)] rounded-lg p-3">
                <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wider block mb-2">
                  Routing
                </span>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-2 text-[10px] font-mono">
                  <div>
                    <span className="text-[var(--text-muted)]">HTTP/HTTPS/FTP:</span>
                    <span className="text-cyan-400 ml-1 font-bold">{engineCapabilities.directEngineId}</span>
                  </div>
                  <div>
                    <span className="text-[var(--text-muted)]">Web Media:</span>
                    <span className="text-[var(--warning)] ml-1 font-bold">{engineCapabilities.mediaEngineId}</span>
                  </div>
                  <div>
                    <span className="text-[var(--text-muted)]">Post-Processing:</span>
                    <span className="text-[var(--accent-primary)] ml-1 font-bold">
                      {engineCapabilities.postProcessorId}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
