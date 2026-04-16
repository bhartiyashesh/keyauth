import { useEffect, useState, useCallback } from 'react';
import PairingView from '../../components/PairingView';
import ConnectedView from '../../components/ConnectedView';
import CodeView from '../../components/CodeView';
import './style.css';

type ConnectionState = 'unpaired' | 'connecting' | 'connected' | 'disconnected' | 'code_received';

interface ActiveCode {
  code: string;
  issuer: string;
  label: string;
  receivedAt: number;
  requestId: string;
}

interface AppState {
  paired: boolean;
  connectionState: ConnectionState;
  activeCodes: ActiveCode[];
  loading: boolean;
}

export default function App() {
  const [state, setState] = useState<AppState>({
    paired: false,
    connectionState: 'unpaired',
    activeCodes: [],
    loading: true,
  });

  // Load initial state from service worker
  useEffect(() => {
    chrome.runtime.sendMessage({ type: 'get_state' }, (response) => {
      if (response) {
        setState({
          paired: response.paired,
          connectionState: response.connectionState ?? 'unpaired',
          activeCodes: response.activeCodes ?? [],
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
        if (changes.activeCodes) {
          setState((prev) => ({
            ...prev,
            activeCodes: (changes.activeCodes.newValue as ActiveCode[]) ?? [],
          }));
        }
      }

      if (areaName === 'local') {
        if (changes.pairing) {
          const hasPairing = !!changes.pairing.newValue;
          setState((prev) => ({
            ...prev,
            paired: hasPairing,
            connectionState: hasPairing ? prev.connectionState : 'unpaired',
          }));
        }
      }
    };

    chrome.storage.onChanged.addListener(listener);
    return () => chrome.storage.onChanged.removeListener(listener);
  }, []);

  const handleDismissCode = useCallback((issuer: string, label: string) => {
    setState((prev) => {
      const remaining = prev.activeCodes.filter(
        c => !(c.issuer === issuer && c.label === label)
      );
      // Update session storage too
      chrome.storage.session.set({
        activeCodes: remaining,
        connectionState: remaining.length > 0 ? 'code_received' : 'connected',
      });
      return {
        ...prev,
        activeCodes: remaining,
        connectionState: remaining.length > 0 ? 'code_received' : 'connected',
      };
    });
  }, []);

  const handleRequestAnother = useCallback(() => {
    chrome.runtime.sendMessage({ type: 'request_code' });
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

  const hasCodes = state.activeCodes.length > 0;

  return (
    <div className="popup">
      <header className="popup-header">
        <h1>KeyAuth</h1>
      </header>
      <div className="popup-body">
        {!state.paired && (
          <PairingView />
        )}

        {state.paired && !hasCodes && state.connectionState === 'connected' && (
          <ConnectedView connectionState="connected" />
        )}

        {state.paired && hasCodes && (
          <div className="codes-list">
            {state.activeCodes.map((c) => (
              <CodeView
                key={`${c.issuer}-${c.label}`}
                code={c.code}
                issuer={c.issuer}
                label={c.label}
                receivedAt={c.receivedAt}
                onDismiss={() => handleDismissCode(c.issuer, c.label)}
              />
            ))}
            <button type="button" className="btn-link request-another" onClick={handleRequestAnother}>
              + Request Another Code
            </button>
          </div>
        )}

        {state.paired && !hasCodes && state.connectionState === 'disconnected' && (
          <ConnectedView connectionState="disconnected" />
        )}

        {state.paired && !hasCodes && state.connectionState === 'connecting' && (
          <ConnectedView connectionState="connecting" />
        )}
      </div>
    </div>
  );
}
