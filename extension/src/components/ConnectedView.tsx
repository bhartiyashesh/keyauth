import StatusDot from './StatusDot';
import AccountList from './AccountList';
import ReconnectingBanner from './ReconnectingBanner';
import type { AccountMetadata } from '../lib/types';

interface ConnectedViewProps {
  connectionState: 'connected' | 'disconnected' | 'connecting';
  accounts: AccountMetadata[];
  domain: string;
}

export default function ConnectedView({ connectionState, accounts, domain }: ConnectedViewProps) {
  const handleUnpair = () => {
    if (confirm('Unpair this device? You will need to scan the QR code again to reconnect.')) {
      chrome.runtime.sendMessage({ type: 'unpair' });
    }
  };

  const showBanner = connectionState === 'disconnected' || connectionState === 'connecting';

  return (
    <div className="connected-view">
      <div className="status-row">
        <StatusDot state={connectionState} />
        <span className="status-text">
          {connectionState === 'connected' && 'Connected'}
          {connectionState === 'disconnected' && 'Disconnected'}
          {connectionState === 'connecting' && 'Connecting...'}
        </span>
        <button className="btn-unpair" onClick={handleUnpair} type="button">
          Unpair
        </button>
      </div>

      <ReconnectingBanner visible={showBanner} />

      <AccountList
        accounts={accounts}
        domain={domain}
        connectionState={connectionState}
      />
    </div>
  );
}
