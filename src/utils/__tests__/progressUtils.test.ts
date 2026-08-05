import { describe, it, expect } from 'vitest';
import { taskProgressInfo } from '../progressUtils';

describe('taskProgressInfo', () => {
  it('returns a real percentage when the total size is known', () => {
    expect(taskProgressInfo({ sizeBytes: 100, downloadedBytes: 25, status: 'downloading' })).toEqual({
      known: true,
      percent: 25,
      indeterminate: false,
      percentLabel: '25%',
    });
  });

  it('caps the percentage at 100 for a completed download', () => {
    expect(taskProgressInfo({ sizeBytes: 100, downloadedBytes: 150, status: 'completed' })).toEqual({
      known: true,
      percent: 100,
      indeterminate: false,
      percentLabel: '100%',
    });
  });

  it('is indeterminate while downloading with an unknown total size', () => {
    // The core "0% then 100%" fix: when the engine has not yet reported a
    // size, the UI must NOT render a misleading 0% — it renders an animated
    // indeterminate bar instead, with a "…" label.
    expect(taskProgressInfo({ sizeBytes: 0, downloadedBytes: 12, status: 'downloading' })).toEqual({
      known: false,
      percent: 0,
      indeterminate: true,
      percentLabel: '…',
    });
  });

  it('is not indeterminate when not downloading (even with unknown size)', () => {
    expect(taskProgressInfo({ sizeBytes: 0, downloadedBytes: 0, status: 'queued' })).toEqual({
      known: false,
      percent: 0,
      indeterminate: false,
      percentLabel: '0%',
    });
    expect(taskProgressInfo({ sizeBytes: 0, downloadedBytes: 0, status: 'completed' })).toEqual({
      known: false,
      percent: 0,
      indeterminate: false,
      percentLabel: '0%',
    });
  });

  it('handles null/undefined tasks gracefully', () => {
    expect(taskProgressInfo(null)).toEqual({
      known: false,
      percent: 0,
      indeterminate: false,
      percentLabel: '0%',
    });
    expect(taskProgressInfo(undefined)).toEqual({
      known: false,
      percent: 0,
      indeterminate: false,
      percentLabel: '0%',
    });
  });

  it('rounds percentages to integers', () => {
    expect(taskProgressInfo({ sizeBytes: 3, downloadedBytes: 1, status: 'downloading' }).percent).toBe(33);
  });
});
