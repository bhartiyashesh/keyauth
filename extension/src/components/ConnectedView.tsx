import StatusDot from './StatusDot';

interface ConnectedViewProps {
  connectionState: 'connected' | 'disconnected' | 'connecting';
}

export default function ConnectedView({ connectionState }: ConnectedViewProps) {
  const isConnected = connectionState === 'connected';

  const handleRequestCode = () => {
    chrome.runtime.sendMessage({ type: 'request_code' });
  };

  const handleUnpair = () => {
    chrome.runtime.sendMessage({ type: 'unpair' });
  };

  return (
    <div className="connected-view">
      <div className="status-row">
        <StatusDot state={connectionState} />
        <span className="status-text">
          {connectionState === 'connected' && 'Connected'}
          {connectionState === 'disconnected' && 'Disconnected'}
          {connectionState === 'connecting' && 'Connecting...'}
        </span>
      </div>

      <button
        className="btn-primary"
        onClick={handleRequestCode}
        disabled={!isConnected}
      >
        Request Code
      </button>

      <button className="btn-danger" onClick={handleUnpair}>
        Unpair
      </button>
    </div>
  );
}
