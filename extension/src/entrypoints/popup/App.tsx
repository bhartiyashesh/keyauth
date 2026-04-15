import { useEffect, useState, useCallback } from 'react';
import PairingView from '../../components/PairingView';
import ConnectedView from '../../components/ConnectedView';
import CodeView from '../../components/CodeView';
import './style.css';

type ConnectionState = 'unpaired' | 'connecting' | 'connected' | 'disconnected' | 'code_received';

interface AppState {
  paired: boolean;
  connectionState: ConnectionState;
  lastCode: string | null;
  codeReceivedAt: number | null;
  loading: boolean;
}

export default function App() {
  const [state, setState] = useState<AppState>({
    paired: false,
    connectionState: 'unpaired',
    lastCode: null,
    codeReceivedAt: null,
    loading: true,
  });

  // Load initial state from service worker
  useEffect(() => {
    chrome.runtime.sendMessage({ type: 'get_state' }, (response) => {
      if (response) {
        setState({
          paired: response.paired,
          connectionState: response.connectionState ?? 'unpaired',
          lastCode: response.lastCode ?? null,
          codeReceivedAt: response.codeReceivedAt ?? null,
          loading: false,
        });
      } else {
        setState((prev) => ({ ...prev, loading: false }));
      }
    });
  }, []);

  // Listen for storage changes from service worker
  useEffect(() => {
    const listener = (
      changes: { [key: string]: chrome.storage.StorageChange },
      areaName: string,
    ) => {
      if (areaName === 'session') {
        if (changes.connectionState) {
          setState((prev) => ({
            ...prev,
            connectionState: changes.connectionState.newValue as ConnectionState,
          }));
        }
        if (changes.lastCode) {
          setState((prev) => ({
            ...prev,
            lastCode: changes.lastCode.newValue as string,
          }));
        }
        if (changes.codeReceivedAt) {
          setState((prev) => ({
            ...prev,
            codeReceivedAt: changes.codeReceivedAt.newValue as number,
          }));
        }
      }

      if (areaName === 'local') {
        if (changes.pairing) {
          const hasPairing = !!changes.pairing.newValue;
          setState((prev) => ({
            ...prev,
            paired: hasPairing,
            // When pairing is cleared, go back to unpaired state
            connectionState: hasPairing ? prev.connectionState : 'unpaired',
          }));
        }
      }
    };

    chrome.storage.onChanged.addListener(listener);
    return () => chrome.storage.onChanged.removeListener(listener);
  }, []);

  const handleCodeDismiss = useCallback(() => {
    chrome.storage.session.set({
      connectionState: 'connected',
      lastCode: null,
      codeReceivedAt: null,
    });
  }, []);

  if (state.loading) {
    return (
      <div className="popup">
        <header className="popup-header">
          <h1>KeyAuth</h1>
        </header>
        <div className="popup-body">
          <p className="loading-text">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="popup">
      <header className="popup-header">
        <h1>KeyAuth</h1>
      </header>
      <div className="popup-body">
        {!state.paired && state.connectionState === 'unpaired' && (
          <PairingView />
        )}

        {state.paired && state.connectionState === 'connected' && (
          <ConnectedView connectionState="connected" />
        )}

        {state.paired && state.connectionState === 'code_received' && state.lastCode && (
          <CodeView
            code={state.lastCode}
            receivedAt={state.codeReceivedAt ?? Date.now()}
            onDismiss={handleCodeDismiss}
          />
        )}

        {state.paired && state.connectionState === 'disconnected' && (
          <ConnectedView connectionState="disconnected" />
        )}

        {state.paired && state.connectionState === 'connecting' && (
          <ConnectedView connectionState="connecting" />
        )}
      </div>
    </div>
  );
}
