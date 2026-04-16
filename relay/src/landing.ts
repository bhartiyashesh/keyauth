export const landingHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Better Authenticator — 2FA codes from phone to browser</title>
  <meta name="description" content="One-click TOTP codes from your phone to your browser. No more switching apps, copying codes, or racing the clock.">
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2280%22>🔐</text></svg>">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    :root {
      --bg: #09090b;
      --surface: #18181b;
      --border: #27272a;
      --text: #fafafa;
      --text-muted: #a1a1aa;
      --accent: #3b82f6;
      --accent-dim: rgba(59, 130, 246, 0.15);
      --green: #22c55e;
      --radius: 12px;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
    }

    .container {
      max-width: 720px;
      margin: 0 auto;
      padding: 0 24px;
    }

    /* Nav */
    nav {
      padding: 20px 0;
      border-bottom: 1px solid var(--border);
    }
    nav .container {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .logo {
      font-size: 18px;
      font-weight: 700;
      letter-spacing: -0.02em;
    }
    .logo span { color: var(--accent); }
    .nav-links a {
      color: var(--text-muted);
      text-decoration: none;
      font-size: 14px;
      margin-left: 24px;
    }
    .nav-links a:hover { color: var(--text); }

    /* Hero */
    .hero {
      padding: 80px 0 60px;
      text-align: center;
    }
    .badge {
      display: inline-block;
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 13px;
      font-weight: 500;
      color: var(--accent);
      background: var(--accent-dim);
      border: 1px solid rgba(59, 130, 246, 0.25);
      margin-bottom: 24px;
    }
    h1 {
      font-size: 44px;
      font-weight: 800;
      letter-spacing: -0.03em;
      line-height: 1.1;
      margin-bottom: 16px;
    }
    h1 .gradient {
      background: linear-gradient(135deg, var(--accent), #8b5cf6);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .hero p {
      font-size: 18px;
      color: var(--text-muted);
      max-width: 480px;
      margin: 0 auto 32px;
    }
    .cta-group {
      display: flex;
      gap: 12px;
      justify-content: center;
      flex-wrap: wrap;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 12px 24px;
      border-radius: 10px;
      font-size: 15px;
      font-weight: 600;
      text-decoration: none;
      transition: all 0.15s;
    }
    .btn-primary {
      background: var(--accent);
      color: white;
    }
    .btn-primary:hover { background: #2563eb; }
    .btn-secondary {
      background: var(--surface);
      color: var(--text);
      border: 1px solid var(--border);
    }
    .btn-secondary:hover { border-color: #52525b; }

    /* Flow */
    .flow {
      padding: 60px 0;
    }
    .flow h2 {
      font-size: 28px;
      font-weight: 700;
      text-align: center;
      margin-bottom: 40px;
      letter-spacing: -0.02em;
    }
    .steps {
      display: grid;
      grid-template-columns: 1fr;
      gap: 16px;
    }
    .step {
      display: flex;
      align-items: flex-start;
      gap: 16px;
      padding: 20px;
      border-radius: var(--radius);
      background: var(--surface);
      border: 1px solid var(--border);
    }
    .step-num {
      width: 32px;
      height: 32px;
      border-radius: 8px;
      background: var(--accent-dim);
      color: var(--accent);
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 14px;
      flex-shrink: 0;
    }
    .step h3 {
      font-size: 15px;
      font-weight: 600;
      margin-bottom: 4px;
    }
    .step p {
      font-size: 14px;
      color: var(--text-muted);
    }

    /* Features */
    .features {
      padding: 40px 0 60px;
    }
    .feature-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 16px;
    }
    .feature {
      padding: 20px;
      border-radius: var(--radius);
      background: var(--surface);
      border: 1px solid var(--border);
    }
    .feature-icon {
      font-size: 24px;
      margin-bottom: 10px;
    }
    .feature h3 {
      font-size: 15px;
      font-weight: 600;
      margin-bottom: 4px;
    }
    .feature p {
      font-size: 13px;
      color: var(--text-muted);
    }

    /* Footer */
    footer {
      padding: 32px 0;
      border-top: 1px solid var(--border);
      text-align: center;
      color: var(--text-muted);
      font-size: 13px;
    }

    @media (max-width: 600px) {
      h1 { font-size: 32px; }
      .hero { padding: 48px 0 40px; }
      .feature-grid { grid-template-columns: 1fr; }
      .cta-group { flex-direction: column; align-items: center; }
    }
  </style>
</head>
<body>
  <nav>
    <div class="container">
      <div class="logo"><span>Better</span> Authenticator</div>
      <div class="nav-links">
        <a href="#how-it-works">How it works</a>
        <a href="#features">Features</a>
      </div>
    </div>
  </nav>

  <section class="hero">
    <div class="container">
      <div class="badge">Open Source &bull; E2E Encrypted</div>
      <h1>2FA codes from<br>phone to <span class="gradient">browser</span></h1>
      <p>One click in Chrome. Face ID on your phone. Code appears instantly. No more switching apps or racing the clock.</p>
      <div class="cta-group">
        <a href="#" class="btn btn-primary">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
          Chrome Extension
        </a>
        <a href="#" class="btn btn-secondary">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.5 2H9a3 3 0 0 0-3 3v14a3 3 0 0 0 3 3h6a3 3 0 0 0 3-3V5a3 3 0 0 0-1.5-3z"/><line x1="12" y1="18" x2="12" y2="18.01"/></svg>
          iOS App
        </a>
      </div>
    </div>
  </section>

  <section class="flow" id="how-it-works">
    <div class="container">
      <h2>Three steps. That's it.</h2>
      <div class="steps">
        <div class="step">
          <div class="step-num">1</div>
          <div>
            <h3>Pair once</h3>
            <p>Scan a QR code in the Chrome extension with your phone. X25519 key exchange happens automatically. One-time setup.</p>
          </div>
        </div>
        <div class="step">
          <div class="step-num">2</div>
          <div>
            <h3>Click "Request Code"</h3>
            <p>On any 2FA login page, click the extension icon. It detects the site and sends a request to your phone.</p>
          </div>
        </div>
        <div class="step">
          <div class="step-num">3</div>
          <div>
            <h3>Approve with Face ID</h3>
            <p>Your phone shows the matched account. One tap + Face ID. The code appears in Chrome instantly, encrypted end-to-end.</p>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section class="features" id="features">
    <div class="container">
      <div class="feature-grid">
        <div class="feature">
          <div class="feature-icon">🔒</div>
          <h3>E2E Encrypted</h3>
          <p>X25519 key exchange + ChaCha20-Poly1305. The relay server never sees your codes.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">📱</div>
          <h3>Secrets stay on phone</h3>
          <p>TOTP seeds never leave your device. Only generated codes are transmitted, and they expire in 30 seconds.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">🌐</div>
          <h3>Domain-aware</h3>
          <p>The extension reads the current site and auto-matches the right account on your phone. No scrolling.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">⚡</div>
          <h3>Auto-refresh</h3>
          <p>After one Face ID approval, your phone keeps sending fresh codes for 5 minutes. No repeated approvals.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">🔄</div>
          <h3>Resilient connection</h3>
          <p>Exponential backoff reconnection, 20-second keepalive pings, and automatic recovery from network drops.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">📋</div>
          <h3>Smart clipboard</h3>
          <p>Click the code to copy. Clipboard auto-clears after 30 seconds. No stale codes sitting around.</p>
        </div>
      </div>
    </div>
  </section>

  <footer>
    <div class="container">
      Better Authenticator &mdash; Open source. Zero dependencies on iOS. Built with privacy first.
    </div>
  </footer>
</body>
</html>`;
