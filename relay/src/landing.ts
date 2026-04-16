export const landingHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Better Authenticator — 2FA codes from phone to browser</title>
  <meta name="description" content="One-click TOTP codes from your phone to your browser. No more switching apps, copying codes, or racing the clock.">
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2280%22>🔐</text></svg>">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Caveat:wght@400;600;700&family=Patrick+Hand&display=swap" rel="stylesheet">
  <style>
    @font-face {
      font-family: 'DxBurst';
      src: url('/fonts/DxBurst-Regular.otf') format('opentype');
      font-weight: normal;
      font-style: normal;
      font-display: swap;
    }

    * { margin: 0; padding: 0; box-sizing: border-box; }

    :root {
      --paper: #fdf6e3;
      --paper-dark: #f5ead0;
      --ink: #2c2c2c;
      --ink-light: #666;
      --accent: #e63946;
      --blue: #457b9d;
      --green: #2a9d8f;
      --pencil: #888;
      --shadow: rgba(0, 0, 0, 0.08);
    }

    body {
      font-family: 'Patrick Hand', cursive;
      background: var(--paper);
      color: var(--ink);
      line-height: 1.7;
      font-size: 18px;
      background-image:
        linear-gradient(rgba(0,0,0,0.03) 1px, transparent 1px);
      background-size: 100% 32px;
    }

    /* Hand-drawn SVG filter */
    .sketch-filter { position: absolute; width: 0; height: 0; }

    .container {
      max-width: 700px;
      margin: 0 auto;
      padding: 0 24px;
    }

    /* Nav */
    nav {
      padding: 20px 0;
      border-bottom: 2px solid var(--ink);
      border-bottom-style: dashed;
    }
    nav .container {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .logo {
      font-family: 'DxBurst', 'Caveat', cursive;
      font-size: 30px;
      font-weight: normal;
      transform: rotate(-1deg);
      display: inline-block;
      letter-spacing: 0.5px;
    }
    .logo .better { color: var(--accent); }
    .nav-links a {
      font-size: 16px;
      color: var(--ink-light);
      text-decoration: none;
      margin-left: 20px;
      border-bottom: 2px dashed transparent;
    }
    .nav-links a:hover {
      border-bottom-color: var(--pencil);
    }

    /* Hero */
    .hero {
      padding: 72px 0 56px;
      text-align: center;
    }
    .hero-doodle {
      font-size: 64px;
      margin-bottom: 16px;
      display: inline-block;
      animation: wiggle 3s ease-in-out infinite;
    }
    @keyframes wiggle {
      0%, 100% { transform: rotate(-3deg); }
      50% { transform: rotate(3deg); }
    }
    h1 {
      font-family: 'DxBurst', 'Caveat', cursive;
      font-size: 56px;
      font-weight: normal;
      line-height: 1.15;
      margin-bottom: 16px;
      transform: rotate(-0.5deg);
    }
    .underline-sketch {
      position: relative;
      display: inline-block;
    }
    .underline-sketch::after {
      content: '';
      position: absolute;
      bottom: 2px;
      left: -4px;
      right: -4px;
      height: 12px;
      background: rgba(230, 57, 70, 0.2);
      border-radius: 50% 40% 50% 45% / 80% 60% 80% 70%;
      z-index: -1;
      transform: rotate(-1deg);
    }
    .hero p {
      font-size: 20px;
      color: var(--ink-light);
      max-width: 460px;
      margin: 0 auto 32px;
    }
    .arrow-down {
      font-size: 32px;
      display: inline-block;
      animation: bounce 2s ease-in-out infinite;
    }
    @keyframes bounce {
      0%, 100% { transform: translateY(0); }
      50% { transform: translateY(8px); }
    }

    /* Buttons */
    .cta-group {
      display: flex;
      gap: 14px;
      justify-content: center;
      flex-wrap: wrap;
      margin-bottom: 24px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 12px 28px;
      font-family: 'Caveat', cursive;
      font-size: 22px;
      font-weight: 600;
      text-decoration: none;
      border: 2.5px solid var(--ink);
      border-radius: 40% 60% 55% 45% / 60% 45% 55% 40%;
      transition: all 0.2s;
      cursor: pointer;
      position: relative;
    }
    .btn:hover {
      transform: translate(-2px, -2px);
      box-shadow: 4px 4px 0 var(--ink);
    }
    .btn-primary {
      background: var(--accent);
      color: white;
      border-color: var(--accent);
    }
    .btn-primary:hover {
      box-shadow: 4px 4px 0 #b22e3a;
    }
    .btn-secondary {
      background: white;
      color: var(--ink);
    }

    /* Steps */
    .flow {
      padding: 48px 0;
    }
    .flow h2 {
      font-family: 'Caveat', cursive;
      font-size: 36px;
      font-weight: 700;
      text-align: center;
      margin-bottom: 32px;
      transform: rotate(0.5deg);
    }
    .steps {
      display: flex;
      flex-direction: column;
      gap: 20px;
    }
    .step {
      display: flex;
      align-items: flex-start;
      gap: 16px;
      padding: 20px;
      background: white;
      border: 2px solid var(--ink);
      position: relative;
    }
    .step:nth-child(1) {
      border-radius: 12px 44px 8px 40px;
      transform: rotate(-0.4deg);
    }
    .step:nth-child(2) {
      border-radius: 40px 8px 44px 12px;
      transform: rotate(0.3deg);
    }
    .step:nth-child(3) {
      border-radius: 8px 40px 12px 44px;
      transform: rotate(-0.2deg);
    }
    .step::after {
      content: '';
      position: absolute;
      inset: 0;
      border-radius: inherit;
      box-shadow: 3px 3px 0 var(--ink);
      pointer-events: none;
    }
    .step-num {
      width: 36px;
      height: 36px;
      background: var(--accent);
      color: white;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: 'Caveat', cursive;
      font-weight: 700;
      font-size: 22px;
      flex-shrink: 0;
      border: 2px solid var(--ink);
    }
    .step h3 {
      font-family: 'Caveat', cursive;
      font-size: 22px;
      font-weight: 700;
      margin-bottom: 2px;
    }
    .step p {
      font-size: 16px;
      color: var(--ink-light);
    }

    /* Connector arrows between steps */
    .step-connector {
      text-align: center;
      font-size: 24px;
      color: var(--pencil);
      margin: -8px 0;
    }

    /* Features */
    .features {
      padding: 32px 0 56px;
    }
    .features h2 {
      font-family: 'Caveat', cursive;
      font-size: 36px;
      font-weight: 700;
      text-align: center;
      margin-bottom: 32px;
      transform: rotate(-0.3deg);
    }
    .feature-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 18px;
    }
    .feature {
      padding: 18px;
      background: white;
      border: 2px solid var(--ink);
      position: relative;
    }
    .feature:nth-child(1) { border-radius: 12px 40px 8px 36px; transform: rotate(-0.5deg); }
    .feature:nth-child(2) { border-radius: 36px 12px 40px 8px; transform: rotate(0.4deg); }
    .feature:nth-child(3) { border-radius: 8px 36px 12px 40px; transform: rotate(0.3deg); }
    .feature:nth-child(4) { border-radius: 40px 8px 36px 12px; transform: rotate(-0.6deg); }
    .feature:nth-child(5) { border-radius: 12px 36px 40px 8px; transform: rotate(0.2deg); }
    .feature:nth-child(6) { border-radius: 36px 12px 8px 40px; transform: rotate(-0.3deg); }
    .feature::after {
      content: '';
      position: absolute;
      inset: 0;
      border-radius: inherit;
      box-shadow: 3px 3px 0 var(--ink);
      pointer-events: none;
    }
    .feature-icon {
      font-size: 28px;
      margin-bottom: 6px;
    }
    .feature h3 {
      font-family: 'Caveat', cursive;
      font-size: 20px;
      font-weight: 700;
      margin-bottom: 2px;
    }
    .feature p {
      font-size: 15px;
      color: var(--ink-light);
    }

    /* Scribble divider */
    .divider {
      text-align: center;
      padding: 16px 0;
      color: var(--pencil);
      font-size: 14px;
      letter-spacing: 8px;
    }

    /* Footer */
    footer {
      padding: 28px 0;
      border-top: 2px dashed var(--pencil);
      text-align: center;
      color: var(--ink-light);
      font-size: 16px;
    }
    footer .heart { color: var(--accent); }

    /* Margin notes / annotations */
    .annotation {
      font-family: 'Caveat', cursive;
      font-size: 16px;
      color: var(--blue);
      transform: rotate(-3deg);
      display: inline-block;
      margin-top: 4px;
    }
    .annotation::before {
      content: '^ ';
    }

    @media (max-width: 600px) {
      h1 { font-size: 38px; }
      .hero { padding: 48px 0 36px; }
      .feature-grid { grid-template-columns: 1fr; }
      .cta-group { flex-direction: column; align-items: center; }
      body { font-size: 16px; }
    }
  </style>
</head>
<body>
  <nav>
    <div class="container">
      <div class="logo"><span class="better">Better</span> Authenticator</div>
      <div class="nav-links">
        <a href="#how-it-works">How?</a>
        <a href="#features">Why?</a>
      </div>
    </div>
  </nav>

  <section class="hero">
    <div class="container">
      <div class="hero-doodle">🔐</div>
      <h1>2FA codes from phone<br>to <span class="underline-sketch">browser</span></h1>
      <p>One click in Chrome. Face ID on your phone. Code appears instantly. No more app-switching.</p>
      <div class="cta-group">
        <a href="#" class="btn btn-primary">Get the Extension</a>
        <a href="#" class="btn btn-secondary">iOS App</a>
      </div>
      <div class="arrow-down">↓</div>
    </div>
  </section>

  <div class="divider">~ ~ ~ ~ ~ ~</div>

  <section class="flow" id="how-it-works">
    <div class="container">
      <h2>How it works (it's stupidly simple)</h2>
      <div class="steps">
        <div class="step">
          <div class="step-num">1</div>
          <div>
            <h3>Pair once 📱💻</h3>
            <p>Scan a QR code in Chrome with your phone. Keys exchange automatically. One-time thing, takes 5 seconds.</p>
            <span class="annotation">end-to-end encrypted from this point on!</span>
          </div>
        </div>
        <div class="step-connector">⋮</div>
        <div class="step">
          <div class="step-num">2</div>
          <div>
            <h3>Click "Request Code" 🖱️</h3>
            <p>On any login page, click the extension. It knows which site you're on and asks your phone for the right code.</p>
            <span class="annotation">domain-aware matching, no scrolling</span>
          </div>
        </div>
        <div class="step-connector">⋮</div>
        <div class="step">
          <div class="step-num">3</div>
          <div>
            <h3>Face ID → done ✨</h3>
            <p>Your phone pops up the right account. One tap, Face ID, code appears in Chrome. Click to copy.</p>
            <span class="annotation">codes auto-refresh for 5 min, no repeated approvals</span>
          </div>
        </div>
      </div>
    </div>
  </section>

  <div class="divider">~ ~ ~ ~ ~ ~</div>

  <section class="features" id="features">
    <div class="container">
      <h2>Why this is better than alt-tabbing</h2>
      <div class="feature-grid">
        <div class="feature">
          <div class="feature-icon">🔒</div>
          <h3>E2E Encrypted</h3>
          <p>X25519 + ChaCha20. The relay server literally cannot read your codes. Zero-knowledge.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">📱</div>
          <h3>Secrets never leave phone</h3>
          <p>TOTP seeds stay on your device. Only generated codes fly through, and they expire in 30 seconds anyway.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">🌐</div>
          <h3>Knows which site</h3>
          <p>On github.com? It auto-matches your GitHub account on the phone. No hunting through a list.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">⚡</div>
          <h3>Auto-refresh</h3>
          <p>One Face ID approval = 5 minutes of fresh codes. It just keeps sending new ones every 30 seconds.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">🔄</div>
          <h3>Stays connected</h3>
          <p>Exponential backoff reconnection. 20-second keepalive pings. Survives network blips like a champ.</p>
        </div>
        <div class="feature">
          <div class="feature-icon">📋</div>
          <h3>Click to copy</h3>
          <p>Click the code, it's copied. Clipboard auto-clears after 30 seconds. No stale codes lying around.</p>
        </div>
      </div>
    </div>
  </section>

  <footer>
    <div class="container">
      Made with <span class="heart">♥</span> &mdash; Open source. Zero iOS dependencies. Privacy first.
    </div>
  </footer>
</body>
</html>`;
