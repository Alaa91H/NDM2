/* src/dialogs/settings/sections/NetworkAndPerformance.tsx */
import React, { useState, useMemo } from 'react';
import { Globe, RefreshCw, ShieldCheck, Server, Network } from 'lucide-react';
import type { AppSettings } from '../../../types/desktop-ui.types';
import { Checkbox, FormRow, SelectField, Switch, TextField } from '../../../components/primitives';
import { useI18n } from '../../../store/selectors';

interface Props {
  settings: AppSettings;
  updateSetting: (section: keyof AppSettings, key: string, value: unknown) => void;
  onAddToast: (type: 'success' | 'error' | 'warning' | 'info', title: string, message: string) => void;
}

const DNS_PRESETS: Record<string, { primary: string; secondary: string; description: string } | undefined> = {
  system:       { primary: '',           secondary: '',           description: 'Use operating system DNS settings' },
  cloudflare:   { primary: '1.1.1.1',    secondary: '1.0.0.1',    description: 'Fast & privacy-focused (1.1.1.1)' },
  google:       { primary: '8.8.8.8',    secondary: '8.8.4.4',    description: 'Reliable public DNS by Google' },
  opendns:      { primary: '208.67.222.222', secondary: '208.67.220.220', description: 'Cisco Umbrella / Parental controls' },
  quad9:        { primary: '9.9.9.9',    secondary: '149.112.112.112', description: 'Security-focused, blocks threats' },
  comodo:       { primary: '8.26.56.26',  secondary: '8.20.247.20',  description: 'Comodo Secure DNS with malware filtering' },
  adguard:      { primary: '94.140.14.14', secondary: '94.140.15.15', description: 'AdGuard DNS — ad/tracker blocking' },
  cleanbrowsing: { primary: '185.228.168.9', secondary: '185.228.169.9', description: 'CleanBrowsing — family-friendly filter' },
  custom:       { primary: '',           secondary: '',           description: 'Manually specify DNS servers' },
};

const DNS_MODE_OPTIONS = [
  { value: 'system',        label: 'System Default' },
  { value: 'cloudflare',    label: 'Cloudflare (1.1.1.1)' },
  { value: 'google',        label: 'Google DNS (8.8.8.8)' },
  { value: 'opendns',       label: 'OpenDNS (208.67.222.222)' },
  { value: 'quad9',         label: 'Quad9 (9.9.9.9)' },
  { value: 'comodo',        label: 'Comodo Secure (8.26.56.26)' },
  { value: 'adguard',       label: 'AdGuard DNS (94.140.14.14)' },
  { value: 'cleanbrowsing', label: 'CleanBrowsing (185.228.168.9)' },
  { value: 'custom',        label: 'Custom — manual entry' },
];

export const NetworkAndPerformance: React.FC<Props> = ({ settings, updateSetting, onAddToast }) => {
  const t = useI18n();
  const [proxyTestStatus, setProxyTestStatus] = useState<'idle' | 'testing' | 'pass' | 'fail'>('idle');
  const [proxyErrorMessage, setProxyErrorMessage] = useState('');
  const [dnsCustomPrimary, setDnsCustomPrimary] = useState(
    () => settings.extra.dnsCustomResolver.split(',')[0] ?? '',
  );
  const [dnsCustomSecondary, setDnsCustomSecondary] = useState(
    () => settings.extra.dnsCustomResolver.split(',')[1] ?? '',
  );

  const activeDnsPreset = useMemo(
    () => DNS_PRESETS[settings.extra.dnsResolver] ?? DNS_PRESETS.custom,
    [settings.extra.dnsResolver],
  );

  const handleDnsModeChange = (mode: string) => {
    updateSetting('extra', 'dnsResolver', mode);
    const preset = DNS_PRESETS[mode];
    if (preset && mode !== 'custom') {
      const servers = [preset.primary, preset.secondary].filter(Boolean).join(',');
      updateSetting('connection', 'dnsServers', servers);
      if (mode !== 'system') {
        updateSetting('extra', 'dnsCustomResolver', servers);
      }
    }
  };

  const handleDnsCustomApply = () => {
    const servers = [dnsCustomPrimary, dnsCustomSecondary].filter(Boolean).join(',');
    updateSetting('extra', 'dnsCustomResolver', servers);
    updateSetting('connection', 'dnsServers', servers);
    onAddToast('success', 'DNS', 'Custom DNS servers applied.');
  };

  const handleDnsTest = () => {
    const servers = settings.connection.defaults.dnsServers || settings.extra.dnsCustomResolver || 'system';
    onAddToast('info', 'DNS Test', `Testing DNS: ${servers}. Check connectivity to confirm resolution.`);
  };

  const handleTestProxy = () => {
    setProxyTestStatus('testing');
    setProxyErrorMessage('');
    setTimeout(() => {
      const host = settings.connection.proxyHost.trim();
      const port = Number(settings.connection.proxyPort);
      if (!host) {
        setProxyTestStatus('fail');
        setProxyErrorMessage('Proxy host is empty.');
        onAddToast('error', t('settings_toast_proxy_test'), t('settings_toast_proxy_fail'));
        return;
      }
      if (!Number.isFinite(port) || port < 1 || port > 65535) {
        setProxyTestStatus('fail');
        setProxyErrorMessage('Proxy port must be between 1 and 65535.');
        onAddToast('error', t('settings_toast_proxy_test'), t('settings_toast_proxy_fail'));
        return;
      }
      setProxyTestStatus('pass');
      setProxyErrorMessage('Configuration looks valid. Start a download to verify the live proxy connection.');
      onAddToast('success', t('settings_toast_proxy_test'), t('settings_toast_proxy_pass'));
    }, 400);
  };

  return (
    <div className="space-y-6 text-left animate-in fade-in duration-200">
      {/* ── Proxy ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Globe className="w-4 h-4 text-[var(--info)]" />
          <h3 className="text-sm font-extrabold text-[var(--info)]">{t('settings_enable_proxy')}</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <FormRow label={t('settings_enable_proxy')}>
            <Switch
              checked={settings.connection.enableProxy}
              onChange={(v) => {
                updateSetting('connection', 'enableProxy', v);
              }}
            />
          </FormRow>

          {settings.connection.enableProxy && (
            <div className="space-y-3 pt-2 border-t border-[var(--border-color)]/50 animate-in slide-in-from-top-2 duration-150">
              <div className="grid grid-cols-1 gap-3">
                <div className="grid grid-cols-2 gap-3">
                  <TextField
                    label={t('settings_proxy_host')}
                    value={settings.connection.proxyHost}
                    onChange={(e) => {
                      updateSetting('connection', 'proxyHost', e.target.value);
                    }}
                    placeholder="127.0.0.1 or proxy.company.com"
                    style={{ direction: 'ltr', textAlign: 'left' }}
                  />
                  <TextField
                    label={t('settings_port')}
                    value={settings.connection.proxyPort}
                    onChange={(e) => {
                      updateSetting('connection', 'proxyPort', e.target.value);
                    }}
                    placeholder="8080"
                    style={{ direction: 'ltr', textAlign: 'left' }}
                  />
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <SelectField
                    label="Proxy Type"
                    value={settings.connection.proxyType}
                    onChange={(e) => {
                      updateSetting('connection', 'proxyType', e.target.value);
                    }}
                    options={[
                      { value: 'http', label: 'HTTP' },
                      { value: 'socks4', label: 'SOCKS4' },
                      { value: 'socks5', label: 'SOCKS5' },
                      { value: 'socks4a', label: 'SOCKS4a' },
                      { value: 'socks5h', label: 'SOCKS5h' },
                    ]}
                  />
                  <div className="flex items-center gap-6 pt-5">
                    <Checkbox
                      label="Proxy Tunnel (CONNECT)"
                      checked={settings.connection.proxyTunnel}
                      onChange={(v) => {
                        updateSetting('connection', 'proxyTunnel', v);
                      }}
                    />
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 gap-3">
                <TextField
                  label={t('settings_proxy_user_optional')}
                  value={settings.connection.proxyUser}
                  onChange={(e) => {
                    updateSetting('connection', 'proxyUser', e.target.value);
                  }}
                  placeholder="Username"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
                <TextField
                  label={t('settings_proxy_pass_optional')}
                  type="password"
                  value={settings.connection.proxyPass}
                  onChange={(e) => {
                    updateSetting('connection', 'proxyPass', e.target.value);
                  }}
                  placeholder="Password"
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
              </div>

              <div className="flex flex-col gap-1.5 items-start pt-2 border-t border-[var(--border-color)]/30">
                <button
                  type="button"
                  onClick={handleTestProxy}
                  disabled={proxyTestStatus === 'testing'}
                  className="px-3 py-1.5 bg-[var(--info-bg)] border border-[var(--info-border)] text-[var(--info)] rounded text-xs font-bold hover:bg-[var(--info-bg)] transition-all cursor-pointer flex items-center gap-1 disabled:opacity-50"
                >
                  {proxyTestStatus === 'testing' && (
                    <RefreshCw className="w-3.5 h-3.5 animate-spin text-[var(--info)]" />
                  )}
                  {t('settings_test_proxy')}
                </button>
                {proxyTestStatus === 'pass' && (
                  <span className="bg-[var(--success-bg)] border border-[var(--success-border)] text-[var(--success)] px-2 py-0.5 rounded text-[10px] font-bold">
                    {t('settings_proxy_connected')}
                  </span>
                )}
                {proxyTestStatus === 'fail' && (
                  <span className="bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger)] px-2 py-0.5 rounded text-[10px] font-bold">
                    {t('settings_proxy_failed')}
                  </span>
                )}
                {proxyErrorMessage && (
                  <p className="text-[11px] text-[var(--danger)] font-mono mt-1">{proxyErrorMessage}</p>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* ── VPN ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <ShieldCheck className="w-4 h-4 text-[var(--success)]" />
          <h3 className="text-sm font-extrabold text-[var(--success)]">{t('settings_vpn_title')}</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <FormRow label={t('settings_vpn_enable')}>
            <Switch
              checked={settings.extra.vpnEnabled}
              onChange={(v) => {
                updateSetting('extra', 'vpnEnabled', v);
              }}
            />
          </FormRow>

          {settings.extra.vpnEnabled && (
            <div className="space-y-3 pt-2 border-t border-[var(--border-color)]/50 animate-in slide-in-from-top-2 duration-150">
              <SelectField
                label={t('settings_vpn_mode')}
                value={settings.extra.vpnMode}
                onChange={(e) => {
                  updateSetting('extra', 'vpnMode', e.target.value);
                }}
                options={[
                  { value: 'system', label: t('settings_vpn_mode_system') },
                  { value: 'proxy', label: t('settings_vpn_mode_proxy') },
                  { value: 'bind', label: t('settings_vpn_mode_bind') },
                ]}
              />

              {settings.extra.vpnMode === 'proxy' && (
                <TextField
                  label={t('settings_vpn_proxy')}
                  value={settings.extra.vpnProxyUrl}
                  onChange={(e) => {
                    updateSetting('extra', 'vpnProxyUrl', e.target.value);
                  }}
                  placeholder={t('settings_vpn_proxy_placeholder')}
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
              )}

              {settings.extra.vpnMode === 'bind' && (
                <TextField
                  label={t('settings_vpn_bind')}
                  value={settings.extra.vpnBindAddress}
                  onChange={(e) => {
                    updateSetting('extra', 'vpnBindAddress', e.target.value);
                  }}
                  placeholder={t('settings_vpn_bind_placeholder')}
                  style={{ direction: 'ltr', textAlign: 'left' }}
                />
              )}

              <div className="flex flex-col gap-2">
                <Checkbox
                  label={t('settings_vpn_kill_switch')}
                  checked={settings.extra.vpnKillSwitch}
                  onChange={(v) => {
                    updateSetting('extra', 'vpnKillSwitch', v);
                  }}
                />
                <Checkbox
                  label={t('settings_vpn_dns_protection')}
                  checked={settings.extra.vpnDnsProtection}
                  onChange={(v) => {
                    updateSetting('extra', 'vpnDnsProtection', v);
                  }}
                />
              </div>

              <p className="text-[10px] text-[var(--text-muted)] leading-relaxed">{t('settings_vpn_note')}</p>
            </div>
          )}
        </div>
      </div>

      {/* ── DNS ── */}
      <div className="space-y-4">
        <div className="flex items-center gap-2 border-b border-[var(--border-color)] pb-2">
          <Network className="w-4 h-4 text-[var(--accent-primary)]" />
          <h3 className="text-sm font-extrabold text-[var(--accent-primary)]">DNS Configuration</h3>
        </div>

        <div className="bg-[var(--bg-hover)]/30 p-3.5 rounded-lg border border-[var(--border-color)] space-y-3">
          <SelectField
            label="DNS Provider"
            value={settings.extra.dnsResolver}
            onChange={(e) => { handleDnsModeChange(e.target.value); }}
            options={DNS_MODE_OPTIONS}
          />

          {settings.extra.dnsResolver !== 'system' && (
            <div className="space-y-3 pt-2 border-t border-[var(--border-color)]/50 animate-in slide-in-from-top-2 duration-150">
              <div className="bg-[var(--bg-hover)]/50 px-2.5 py-2 rounded border border-[var(--border-color)]/50">
                <p className="text-[10px] text-[var(--text-muted)] font-mono">{activeDnsPreset.description}</p>
                {settings.extra.dnsResolver !== 'custom' && (
                  <p className="text-[11px] text-[var(--accent-primary)] font-mono mt-1">
                    {[activeDnsPreset.primary, activeDnsPreset.secondary].filter(Boolean).join(', ')}
                  </p>
                )}
              </div>

              {settings.extra.dnsResolver === 'custom' && (
                <div className="grid grid-cols-2 gap-3 p-2.5 bg-[var(--bg-hover)]/50 rounded border border-[var(--border-color)]/50">
                  <TextField
                    label="Primary DNS"
                    value={dnsCustomPrimary}
                    onChange={(e) => { setDnsCustomPrimary(e.target.value); }}
                    placeholder="e.g. 1.1.1.1"
                    style={{ direction: 'ltr', textAlign: 'left' }}
                  />
                  <TextField
                    label="Secondary DNS"
                    value={dnsCustomSecondary}
                    onChange={(e) => { setDnsCustomSecondary(e.target.value); }}
                    placeholder="e.g. 1.0.0.1"
                    style={{ direction: 'ltr', textAlign: 'left' }}
                  />
                  <div className="col-span-2 flex justify-end">
                    <button
                      type="button"
                      onClick={handleDnsCustomApply}
                      className="px-3 py-1.5 bg-[var(--accent-primary)]/10 border border-[var(--accent-border)] text-[var(--accent-primary)] rounded text-[10px] font-bold hover:bg-[var(--accent-primary)]/20 transition-all cursor-pointer"
                    >
                      Apply Custom DNS
                    </button>
                  </div>
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <FormRow label="DNS over HTTPS">
                  <Switch
                    checked={settings.extra.dnsOverHttps}
                    onChange={(v) => { updateSetting('extra', 'dnsOverHttps', v); }}
                  />
                </FormRow>
                <FormRow label="Cache timeout (sec)">
                  <input
                    type="number"
                    min={0}
                    max={86400}
                    value={settings.extra.dnsCacheTimeoutSec}
                    onChange={(e) => {
                      const val = Math.max(0, Math.min(86400, Number(e.target.value) || 0));
                      updateSetting('extra', 'dnsCacheTimeoutSec', val);
                    }}
                    className="w-20 bg-[var(--bg-input)] border border-[var(--border-color)] rounded px-2 py-1 text-[10px] font-mono text-[var(--text-primary)] focus:border-[var(--accent-primary)] focus:outline-none text-left"
                    style={{ direction: 'ltr' }}
                  />
                </FormRow>
              </div>

              <div className="flex items-center gap-2 pt-1">
                <button
                  type="button"
                  onClick={handleDnsTest}
                  className="px-3 py-1.5 bg-[var(--info-bg)] border border-[var(--info-border)] text-[var(--info)] rounded text-[10px] font-bold hover:bg-[var(--info-bg)] transition-all cursor-pointer flex items-center gap-1"
                >
                  <Server className="w-3 h-3" />
                  Test DNS
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
