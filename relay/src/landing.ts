export const landingHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Better Authenticator</title>
  <meta name="description" content="2FA codes from phone to browser. One click.">
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

    body {
      background: #0a0a0a;
      color: #f0f0f0;
      font-family: 'Patrick Hand', cursive;
      min-height: 100vh;
      overflow-x: hidden;
    }

    /* ===== HERO ===== */
    .hero {
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 40px 24px;
      position: relative;
    }

    .hero-logo {
      font-family: 'DxBurst', 'Caveat', cursive;
      font-size: 96px;
      font-weight: normal;
      line-height: 1;
      margin-bottom: 24px;
      letter-spacing: 2px;
    }
    .hero-logo .red { color: #e63946; }

    .hero-tagline {
      font-family: 'Caveat', cursive;
      font-size: 32px;
      color: #888;
      margin-bottom: 48px;
      transform: rotate(-1deg);
    }

    .hero-steps {
      display: flex;
      gap: 48px;
      align-items: center;
      margin-bottom: 56px;
      flex-wrap: wrap;
      justify-content: center;
    }
    .hero-step {
      font-family: 'Caveat', cursive;
      font-size: 26px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
    }
    .hero-step-icon {
      font-size: 48px;
    }
    .hero-step-arrow {
      font-size: 32px;
      color: #555;
    }

    .hero-cta {
      display: flex;
      gap: 16px;
      flex-wrap: wrap;
      justify-content: center;
      margin-bottom: 40px;
    }
    .btn {
      font-family: 'Caveat', cursive;
      font-size: 26px;
      font-weight: 600;
      padding: 16px 40px;
      text-decoration: none;
      border: 3px solid #333;
      border-radius: 40% 60% 55% 45% / 60% 45% 55% 40%;
      transition: all 0.2s;
      cursor: pointer;
      display: inline-block;
    }
    .btn:hover {
      transform: translate(-2px, -2px);
      box-shadow: 5px 5px 0 #333;
    }
    .btn-red {
      background: #e63946;
      color: white;
      border-color: #e63946;
    }
    .btn-red:hover {
      box-shadow: 5px 5px 0 #b22e3a;
    }
    .btn-ghost {
      background: transparent;
      color: #f0f0f0;
    }

    .hero-note {
      font-family: 'Caveat', cursive;
      font-size: 18px;
      color: #555;
    }

    /* ===== FEATURES (minimal) ===== */
    .features {
      padding: 80px 24px;
      max-width: 800px;
      margin: 0 auto;
    }
    .features h2 {
      font-family: 'DxBurst', 'Caveat', cursive;
      font-size: 48px;
      text-align: center;
      margin-bottom: 48px;
    }
    .feature-row {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 24px;
      text-align: center;
    }
    .feature-item {
      padding: 24px 16px;
      border: 2px solid #222;
      border-radius: 12px 40px 8px 36px;
      background: #111;
    }
    .feature-item:nth-child(2) { border-radius: 40px 12px 36px 8px; }
    .feature-item:nth-child(3) { border-radius: 8px 36px 12px 40px; }
    .feature-item .icon { font-size: 36px; margin-bottom: 8px; }
    .feature-item h3 {
      font-family: 'Caveat', cursive;
      font-size: 22px;
      margin-bottom: 4px;
    }
    .feature-item p {
      font-size: 15px;
      color: #888;
    }

    /* ===== FOOTER ===== */
    footer {
      text-align: center;
      padding: 32px 24px;
      color: #444;
      font-size: 16px;
      border-top: 2px dashed #222;
    }
    footer .heart { color: #e63946; }

    @media (max-width: 600px) {
      .hero-logo { font-size: 56px; }
      .hero-tagline { font-size: 24px; }
      .hero-steps { gap: 24px; }
      .hero-step { font-size: 20px; }
      .hero-step-icon { font-size: 36px; }
      .hero-step-arrow { display: none; }
      .btn { font-size: 22px; padding: 14px 32px; }
      .features h2 { font-size: 36px; }
      .feature-row { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>

  <section class="hero">
    <div class="hero-logo"><span class="red">Better</span> Authenticator</div>
    <div class="hero-tagline">2FA codes from phone to browser. One click.</div>

    <div class="hero-steps">
      <div class="hero-step">
        <div class="hero-step-icon">📱</div>
        Pair once
      </div>
      <div class="hero-step-arrow">→</div>
      <div class="hero-step">
        <div class="hero-step-icon">🖱️</div>
        Click
      </div>
      <div class="hero-step-arrow">→</div>
      <div class="hero-step">
        <div class="hero-step-icon">🔓</div>
        Face ID
      </div>
      <div class="hero-step-arrow">→</div>
      <div class="hero-step">
        <div class="hero-step-icon">✨</div>
        Done
      </div>
    </div>

    <div class="hero-cta">
      <a href="#" class="btn btn-red">Chrome Extension</a>
      <a href="#" class="btn btn-ghost">iOS App</a>
    </div>

    <div class="hero-note">Open source &bull; E2E encrypted &bull; Secrets never leave your phone</div>
  </section>

  <section class="features">
    <h2>Why?</h2>
    <div class="feature-row">
      <div class="feature-item">
        <div class="icon">🔒</div>
        <h3>Zero-knowledge relay</h3>
        <p>Server can't read your codes. Ever.</p>
      </div>
      <div class="feature-item">
        <div class="icon">🌐</div>
        <h3>Knows the site</h3>
        <p>Auto-matches the right account.</p>
      </div>
      <div class="feature-item">
        <div class="icon">⚡</div>
        <h3>Auto-refresh</h3>
        <p>One approval, 5 min of fresh codes.</p>
      </div>
    </div>
  </section>

  <footer>
    Made with <span class="heart">♥</span> &mdash; Privacy first
  </footer>

</body>
</html>`;
