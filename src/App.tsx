import React from 'react';
import { AppStoreProvider } from './state/appStore';
import { AppShell } from './components/AppShell';
import { EngineCapabilityProvider } from './capabilities/EngineCapabilityContext';
import { DetachedProgressWindow } from './dialogs/download/DetachedProgressWindow';
import { detachedMode, detachedTaskId } from './utils/windowMode';
import { ErrorBoundary } from './components/ErrorBoundary';

export default function App() {
  // Detached companion windows (e.g. a popped-out progress panel) reuse the
  // same providers so they stay wired to the live daemon connection.
  if (detachedMode() === 'progress') {
    return (
      <ErrorBoundary>
        <AppStoreProvider>
          <EngineCapabilityProvider>
            <DetachedProgressWindow taskId={detachedTaskId() ?? ''} />
          </EngineCapabilityProvider>
        </AppStoreProvider>
      </ErrorBoundary>
    );
  }

  return (
    <ErrorBoundary>
      <AppStoreProvider>
        <EngineCapabilityProvider>
          <AppShell />
        </EngineCapabilityProvider>
      </AppStoreProvider>
    </ErrorBoundary>
  );
}
