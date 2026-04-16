export default defineContentScript({
  matches: ['<all_urls>'],
  runAt: 'document_idle',

  main() {
    const BADGE_ID = 'keyauth-fill-badge';
    const BADGE_SIZE = 24;
    let activeBadge: HTMLElement | null = null;
    let activeInput: HTMLInputElement | null = null;

    // ---------- TOTP Field Detection ----------

    function isTotpField(el: HTMLInputElement): boolean {
      const autocomplete = el.getAttribute('autocomplete') || '';
      if (autocomplete === 'one-time-code') return true;

      const name = (el.name || '').toLowerCase();
      const id = (el.id || '').toLowerCase();
      const placeholder = (el.placeholder || '').toLowerCase();
      const ariaLabel = (el.getAttribute('aria-label') || '').toLowerCase();
      const allText = `${name} ${id} ${placeholder} ${ariaLabel}`;

      // Check for TOTP-related keywords
      const totpKeywords = [
        'otp', 'totp', 'mfa', '2fa', 'two-factor', 'two_factor',
        'verification', 'verify', 'auth-code', 'authcode',
        'security-code', 'security_code', 'one-time', 'onetime',
        '6-digit', '6digit', 'token',
      ];
      if (totpKeywords.some((kw) => allText.includes(kw))) return true;

      // Check for numeric-only 6-digit input patterns
      const maxLength = el.maxLength;
      const inputMode = el.inputMode;
      if (
        (maxLength === 6 || maxLength === 7) &&
        (inputMode === 'numeric' || el.type === 'tel' || el.pattern?.includes('[0-9]'))
      ) {
        return true;
      }

      // Check nearby label text
      const label = el.labels?.[0]?.textContent?.toLowerCase() || '';
      if (totpKeywords.some((kw) => label.includes(kw))) return true;

      return false;
    }

    // ---------- Badge UI ----------

    function createBadge(): HTMLElement {
      const badge = document.createElement('div');
      badge.id = BADGE_ID;
      badge.title = 'Fill code from KeyAuth';
      Object.assign(badge.style, {
        position: 'absolute',
        width: `${BADGE_SIZE}px`,
        height: `${BADGE_SIZE}px`,
        cursor: 'pointer',
        zIndex: '2147483647',
        borderRadius: '4px',
        background: '#3b82f6',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: '0 1px 4px rgba(0,0,0,0.2)',
        transition: 'transform 0.15s, opacity 0.15s',
        opacity: '0.85',
      });
      // Key icon as SVG
      badge.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.78 7.78 5.5 5.5 0 0 1 7.78-7.78zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>
      </svg>`;

      badge.addEventListener('mouseenter', () => {
        badge.style.opacity = '1';
        badge.style.transform = 'scale(1.1)';
      });
      badge.addEventListener('mouseleave', () => {
        badge.style.opacity = '0.85';
        badge.style.transform = 'scale(1)';
      });

      badge.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        requestAndFill();
      });

      return badge;
    }

    function positionBadge(badge: HTMLElement, input: HTMLInputElement) {
      const rect = input.getBoundingClientRect();
      badge.style.top = `${window.scrollY + rect.top + (rect.height - BADGE_SIZE) / 2}px`;
      badge.style.left = `${window.scrollX + rect.right - BADGE_SIZE - 6}px`;
    }

    function showBadge(input: HTMLInputElement) {
      removeBadge();
      const badge = createBadge();
      document.body.appendChild(badge);
      positionBadge(badge, input);
      activeBadge = badge;
      activeInput = input;
    }

    function removeBadge() {
      if (activeBadge) {
        activeBadge.remove();
        activeBadge = null;
      }
    }

    // ---------- Code Request + Fill ----------

    async function requestAndFill() {
      if (!activeInput) return;
      const input = activeInput;

      // Show loading state on badge
      if (activeBadge) {
        activeBadge.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5"><circle cx="12" cy="12" r="10" stroke-dasharray="31.4" stroke-dashoffset="10"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.8s" repeatCount="indefinite"/></circle></svg>`;
      }

      // Request code from service worker
      chrome.runtime.sendMessage({ type: 'request_code' }, (response) => {
        if (!response?.ok) {
          // Show error briefly then restore
          if (activeBadge) {
            activeBadge.style.background = '#ef4444';
            setTimeout(() => {
              if (activeBadge) activeBadge.style.background = '#3b82f6';
              restoreBadgeIcon();
            }, 1500);
          }
          return;
        }
      });

      // Listen for the code to arrive via storage
      const listener = (
        changes: { [key: string]: chrome.storage.StorageChange },
        areaName: string,
      ) => {
        if (areaName === 'session' && changes.lastCode?.newValue) {
          const code = changes.lastCode.newValue as string;
          chrome.storage.onChanged.removeListener(listener);

          // Fill the input
          fillInput(input, code);

          // Show success on badge
          if (activeBadge) {
            activeBadge.style.background = '#22c55e';
            activeBadge.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;
            setTimeout(() => removeBadge(), 2000);
          }
        }
      };

      chrome.storage.onChanged.addListener(listener);

      // Timeout: stop listening after 30 seconds
      setTimeout(() => {
        chrome.storage.onChanged.removeListener(listener);
        restoreBadgeIcon();
      }, 30_000);
    }

    function fillInput(input: HTMLInputElement, code: string) {
      // Set value and dispatch events so frameworks (React, Angular, Vue) detect the change
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype, 'value'
      )?.set;
      nativeInputValueSetter?.call(input, code);

      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function restoreBadgeIcon() {
      if (activeBadge) {
        activeBadge.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.78 7.78 5.5 5.5 0 0 1 7.78-7.78zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>
        </svg>`;
      }
    }

    // ---------- Scanning ----------

    function scanForTotpFields() {
      const inputs = document.querySelectorAll<HTMLInputElement>(
        'input[type="text"], input[type="tel"], input[type="number"], input:not([type])'
      );
      for (const input of inputs) {
        if (isTotpField(input) && isVisible(input)) {
          showBadge(input);
          return; // Show badge on first match only
        }
      }
    }

    function isVisible(el: HTMLElement): boolean {
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && window.getComputedStyle(el).visibility !== 'hidden';
    }

    // ---------- Init ----------

    // Check if we're paired before doing anything
    chrome.runtime.sendMessage({ type: 'get_state' }, (response) => {
      if (!response?.paired) return; // Not paired -- don't scan

      // Initial scan
      scanForTotpFields();

      // Watch for dynamically added fields (SPAs)
      const observer = new MutationObserver(() => {
        if (!activeBadge) scanForTotpFields();
      });
      observer.observe(document.body, { childList: true, subtree: true });

      // Reposition badge on scroll/resize
      window.addEventListener('scroll', () => {
        if (activeBadge && activeInput) positionBadge(activeBadge, activeInput);
      }, { passive: true });
      window.addEventListener('resize', () => {
        if (activeBadge && activeInput) positionBadge(activeBadge, activeInput);
      });
    });
  },
});
