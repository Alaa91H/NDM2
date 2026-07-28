import React from 'react';
import { Server, Shield, ShieldAlert } from 'lucide-react';
import { useI18n } from '../store/selectors';

interface SchedulerActionsTabProps {
  shutdownOnComplete: boolean;
  onShutdownChange: (v: boolean) => void;
  hangupOnComplete: boolean;
  onHangupChange: (v: boolean) => void;
  exitOnComplete: boolean;
  onExitChange: (v: boolean) => void;
}

export const SchedulerActionsTab: React.FC<SchedulerActionsTabProps> = ({
  shutdownOnComplete,
  onShutdownChange,
  hangupOnComplete,
  onHangupChange,
  exitOnComplete,
  onExitChange,
}) => {
  const t = useI18n();

  return (
    <div className="space-y-4">
      <h3 className="text-xs font-bold text-[var(--text-muted)] border-b border-[var(--border-color)] pb-1.5">
        {t('sched_actions_on_complete')}
      </h3>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label className="flex items-center justify-between p-3 bg-[var(--bg-surface)] border border-[var(--border-color)] hover:border-[var(--accent-border)] rounded-xl cursor-pointer hover:bg-[var(--bg-hover)] shadow-sm">
          <div className="flex items-center gap-2.5">
            <Server className="w-4 h-4 text-[var(--danger)]" />
            <div className="flex flex-col">
              <span className="text-xs font-bold text-[var(--text-primary)]">{t('sched_action_shutdown')}</span>
              <span className="text-[10px] text-[var(--text-muted)]">{t('sched_action_shutdown_desc')}</span>
            </div>
          </div>
          <input
            type="checkbox"
            checked={shutdownOnComplete}
            onChange={(e) => {
              onShutdownChange(e.target.checked);
            }}
            className="w-4.5 h-4.5 text-[var(--accent-primary)] focus-visible:ring-[var(--accent-primary)] cursor-pointer"
          />
        </label>

        <label className="flex items-center justify-between p-3 bg-[var(--bg-surface)] border border-[var(--border-color)] hover:border-[var(--accent-border)] rounded-xl cursor-pointer hover:bg-[var(--bg-hover)] shadow-sm">
          <div className="flex items-center gap-2.5">
            <Shield className="w-4 h-4 text-[var(--info)]" />
            <div className="flex flex-col">
              <span className="text-xs font-bold text-[var(--text-primary)]">{t('sched_action_sleep')}</span>
              <span className="text-[10px] text-[var(--text-muted)]">{t('sched_action_sleep_desc')}</span>
            </div>
          </div>
          <input
            type="checkbox"
            checked={hangupOnComplete}
            onChange={(e) => {
              onHangupChange(e.target.checked);
            }}
            className="w-4.5 h-4.5 text-[var(--accent-primary)] focus-visible:ring-[var(--accent-primary)] cursor-pointer"
          />
        </label>

        <label className="flex items-center justify-between p-3 bg-[var(--bg-surface)] border border-[var(--border-color)] hover:border-[var(--accent-border)] rounded-xl cursor-pointer hover:bg-[var(--bg-hover)] shadow-sm">
          <div className="flex items-center gap-2.5">
            <ShieldAlert className="w-4 h-4 text-[var(--warning)]" />
            <div className="flex flex-col">
              <span className="text-xs font-bold text-[var(--text-primary)]">{t('sched_action_exit')}</span>
              <span className="text-[10px] text-[var(--text-muted)]">{t('sched_action_exit_desc')}</span>
            </div>
          </div>
          <input
            type="checkbox"
            checked={exitOnComplete}
            onChange={(e) => {
              onExitChange(e.target.checked);
            }}
            className="w-4.5 h-4.5 text-[var(--accent-primary)] focus-visible:ring-[var(--accent-primary)] cursor-pointer"
          />
        </label>
      </div>
    </div>
  );
};
