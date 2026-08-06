import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { DownloadItem } from '../../../types/desktop-ui.types';

// vi.mock factories are hoisted above the imports, so any mutable state they
// need must come from vi.hoisted (declared before the mocks run).
const { tasksMock, setTitle } = vi.hoisted(() => ({
  tasksMock: [] as DownloadItem[],
  setTitle: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true }));
vi.mock('@tauri-apps/api/window', () => ({
  getCurrentWindow: () => ({
    minimize: vi.fn().mockResolvedValue(undefined),
    close: vi.fn().mockResolvedValue(undefined),
    setTitle,
  }),
}));
vi.mock('../../../store/selectors', () => ({
  useTaskData: () => tasksMock,
  useBridgeData: () => ({ status: 'connected' }),
  useI18n: () => (k: string) => {
    if (k === 'app_name') return 'NOVA Download Manager';
    return k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  },
}));
// Keep the real ActiveProgressDialog module untouched; the lazy import only
// resolves once the Suspense boundary commits, and we assert on the title bar.
vi.mock('../../../components/Logo', () => ({
  Logo: () => <svg data-testid="logo" />,
}));

import { DetachedProgressWindow } from '../DetachedProgressWindow';

const baseTask: DownloadItem = {
  id: 't1',
  name: 'file.bin',
  url: 'https://example.com/file.bin',
  fileType: 'other',
  status: 'downloading',
  sizeBytes: 0,
  downloadedBytes: 0,
  speedBytesPerSec: 1024,
  timeLeftSeconds: 10,
  elapsedSeconds: 2,
  dateAdded: '2026-01-01T00:00:00Z',
  category: 'other',
  queueId: 'main',
  connections: 2,
  resumable: true,
  savePath: '/tmp/file.bin',
  description: '',
  segments: [],
};

describe('DetachedProgressWindow — unified live progress', () => {
  beforeEach(() => {
    tasksMock.length = 0;
    setTitle.mockClear();
  });

  it('shows the live percent label and compact bar in the title bar, and sets the OS title with the percent', async () => {
    tasksMock.push({ ...baseTask, sizeBytes: 0, status: 'downloading' });
    render(<DetachedProgressWindow taskId="t1" />);

    // Indeterminate: title bar shows "…" and a sweeping compact bar.
    expect(screen.getByText('…')).toBeInTheDocument();
    expect(screen.getByTestId('progress-sweep').className).toContain('opacity-100');
    // OS window title carries the indeterminate marker.
    await waitFor(() => expect(setTitle).toHaveBeenCalledWith('… — file.bin'));
  });

  it('reflects a discovered size as a real percentage in the title bar and OS title', async () => {
    tasksMock.push({ ...baseTask, sizeBytes: 1000, downloadedBytes: 500 });
    render(<DetachedProgressWindow taskId="t1" />);

    expect(screen.getByText('50%')).toBeInTheDocument();
    const fill = screen.getByTestId('progress-fill');
    expect(fill).toHaveStyle({ width: '50%' });
    expect(screen.getByTestId('progress-sweep').className).toContain('opacity-0');
    await waitFor(() => expect(setTitle).toHaveBeenCalledWith('50% — file.bin'));
  });

  it('falls back to the app name in the OS title when no task matches', async () => {
    render(<DetachedProgressWindow taskId="missing" />);
    expect(screen.queryByText('…')).not.toBeInTheDocument();
    await waitFor(() => expect(setTitle).toHaveBeenCalledWith('NOVA Download Manager'));
  });
});
