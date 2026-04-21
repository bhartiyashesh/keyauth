import { attemptFill } from './content-utils';

export default defineContentScript({
  matches: ['*://*/*'],
  runAt: 'document_idle',
  main(ctx) {
    // Listen for fill commands from service worker (D-05: passive, no proactive scanning)
    chrome.runtime.onMessage.addListener(
      (message: { type: string; code?: string }, _sender, sendResponse) => {
        if (message.type === 'fill_code' && message.code) {
          const filled = attemptFill(document, message.code);
          sendResponse({ filled });
        }
        return true; // Keep channel open for async
      }
    );

    // Clean up on context invalidation (extension update/reload)
    ctx.onInvalidated(() => {
      // No persistent UI to clean up -- content script is invisible
    });
  },
});
