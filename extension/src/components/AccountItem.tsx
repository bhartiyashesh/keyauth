import { domainMatchesIssuer } from '../lib/domain-match';
import type { AccountMetadata } from '../lib/types';

interface AccountItemProps {
  account: AccountMetadata;
  domain: string;
  requesting: boolean;
  onSelect: (account: AccountMetadata) => void;
}

export default function AccountItem({ account, domain, requesting, onSelect }: AccountItemProps) {
  const isMatched = domainMatchesIssuer(domain, account.issuer);
  const initial = (account.issuer || account.label || '?')[0].toUpperCase();
  const displayName = account.issuer || account.label || 'Unknown';
  const badgeColor = `hsl(${[...displayName].reduce((a, c) => a + c.charCodeAt(0), 0) % 360}, 55%, 50%)`;

  return (
    <button
      className={`account-item ${isMatched ? 'account-item--matched' : ''} ${requesting ? 'account-item--requesting' : ''}`}
      onClick={() => onSelect(account)}
      disabled={requesting}
      type="button"
    >
      <div className="account-item-badge" style={{ backgroundColor: badgeColor }}>
        {initial}
      </div>
      <div className="account-item-info">
        <span className="account-item-issuer">{displayName}</span>
        {account.issuer && account.label && (
          <span className="account-item-label">{account.label}</span>
        )}
      </div>
      {isMatched && <span className="account-item-hint">Suggested for this site</span>}
      {requesting && <span className="account-item-status">Waiting for approval...</span>}
    </button>
  );
}
