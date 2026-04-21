import { useState } from 'react';
import AccountItem from './AccountItem';
import type { AccountMetadata } from '../lib/types';
import { sortAccountsByDomain } from '../lib/domain-match';

interface AccountListProps {
  accounts: AccountMetadata[];
  domain: string;
  connectionState: 'connected' | 'disconnected' | 'connecting';
}

export default function AccountList({ accounts, domain, connectionState }: AccountListProps) {
  const [requestingId, setRequestingId] = useState<string | null>(null);
  const isConnected = connectionState === 'connected';
  const sorted = sortAccountsByDomain(accounts, domain);

  const handleSelect = (account: AccountMetadata) => {
    if (!isConnected) return;
    setRequestingId(account.id);
    chrome.runtime.sendMessage(
      { type: 'request_code', accountId: account.id, domain },
      (response) => {
        if (!response?.ok) {
          setRequestingId(null);
        }
      }
    );
  };

  if (accounts.length === 0) {
    return (
      <div className="account-list-empty">
        <p className="account-list-empty-heading">No accounts yet</p>
        <p className="account-list-empty-body">
          Open KeyAuth on your iPhone to sync your accounts. Make sure both devices are connected.
        </p>
      </div>
    );
  }

  return (
    <div className="account-list">
      {sorted.map((account) => (
        <AccountItem
          key={account.id}
          account={account}
          domain={domain}
          requesting={requestingId === account.id}
          onSelect={handleSelect}
        />
      ))}
    </div>
  );
}
