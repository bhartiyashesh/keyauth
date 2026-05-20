import React, { useMemo, useState } from "react";
import { motion } from "framer-motion";

function Icon({ name, className = "" }) {
  const common = {
    className,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2.35,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": "true",
  };

  const icons = {
    arrowRight: (
      <svg {...common}>
        <path d="M5 12h14" />
        <path d="m13 6 6 6-6 6" />
      </svg>
    ),
    check: (
      <svg {...common}>
        <path d="m5 12 4 4L19 6" />
      </svg>
    ),
    xmark: (
      <svg {...common}>
        <path d="M6 6l12 12" />
        <path d="M18 6 6 18" />
      </svg>
    ),
    chrome: (
      <svg {...common}>
        <circle cx="12" cy="12" r="9" />
        <circle cx="12" cy="12" r="3.1" />
        <path d="M12 3h7.5" />
        <path d="M4.3 7.5 8.2 14" />
        <path d="m15.8 14-3.9 7" />
      </svg>
    ),
    keyboard: (
      <svg {...common}>
        <rect x="3" y="5" width="18" height="14" rx="3" />
        <path d="M7 9h.01M11 9h.01M15 9h.01M19 9h.01" />
        <path d="M7 13h.01M11 13h.01M15 13h.01M19 13h.01" />
        <path d="M8 17h8" />
      </svg>
    ),
    puzzle: (
      <svg {...common}>
        <path d="M9 3h6v4a2 2 0 1 0 0 4v4h-4a2 2 0 1 1-4 0H3V9h4a2 2 0 1 0 2-2V3Z" />
        <path d="M15 15h6v6h-6" />
      </svg>
    ),
    shieldCheck: (
      <svg {...common}>
        <path d="M12 3 20 6v6c0 5-3.4 7.8-8 9-4.6-1.2-8-4-8-9V6l8-3Z" />
        <path d="m8.5 12 2.2 2.2 4.8-5" />
      </svg>
    ),
    timerReset: (
      <svg {...common}>
        <path d="M10 2h4" />
        <path d="M12 14v-4" />
        <path d="M8 6.4a8 8 0 1 1-2.5 2.2" />
        <path d="M4 5v4h4" />
      </svg>
    ),
    zap: (
      <svg {...common}>
        <path d="M13 2 4 14h7l-1 8 10-13h-7l1-7Z" />
      </svg>
    ),
    lock: (
      <svg {...common}>
        <rect x="5" y="10" width="14" height="10" rx="2.5" />
        <path d="M8 10V7a4 4 0 0 1 8 0v3" />
      </svg>
    ),
    command: (
      <svg {...common}>
        <path d="M9 9h6v6H9z" />
        <path d="M9 9H6.5A2.5 2.5 0 1 1 9 6.5V9Z" />
        <path d="M15 9V6.5A2.5 2.5 0 1 1 17.5 9H15Z" />
        <path d="M15 15h2.5A2.5 2.5 0 1 1 15 17.5V15Z" />
        <path d="M9 15v2.5A2.5 2.5 0 1 1 6.5 15H9Z" />
      </svg>
    ),
    cloud: (
      <svg {...common}>
        <path d="M17.5 19a4.5 4.5 0 0 0 0-9h-1.05A6 6 0 0 0 5 9a4 4 0 0 0 0 8h.5" />
        <path d="M9 19h8.5" />
      </svg>
    ),
    phone: (
      <svg {...common}>
        <rect x="7" y="2" width="10" height="20" rx="2.6" />
        <path d="M11 19h2" />
      </svg>
    ),
    code: (
      <svg {...common}>
        <path d="m9 18-6-6 6-6" />
        <path d="m15 6 6 6-6 6" />
      </svg>
    ),
    faceid: (
      <svg {...common}>
        <path d="M3 8V6a3 3 0 0 1 3-3h2" />
        <path d="M16 3h2a3 3 0 0 1 3 3v2" />
        <path d="M21 16v2a3 3 0 0 1-3 3h-2" />
        <path d="M8 21H6a3 3 0 0 1-3-3v-2" />
        <path d="M9 10v1" />
        <path d="M15 10v1" />
        <path d="M12 10v4" />
        <path d="M9 16s.8 1 3 1 3-1 3-1" />
      </svg>
    ),
  };

  return icons[name] || null;
}

function LogoMark({ className = "", inverted = false }) {
  const outer = inverted ? "bg-white" : "bg-black";
  const inner = inverted ? "bg-black" : "bg-white";
  const ink = inverted ? "bg-white" : "bg-black";

  return (
    <div className={`relative grid place-items-center overflow-hidden ${outer} ${className}`} aria-hidden="true">
      <div className={`relative flex h-[38%] w-[74%] items-center justify-center gap-[5%] rounded-[26%] ${inner}`}>
        {[0, 1, 2, 3, 4, 5].map((dot) => (
          <motion.span
            key={dot}
            initial={{ opacity: 0, scale: 0.7 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: dot * 0.06, duration: 0.24 }}
            className={`aspect-square h-[30%] rounded-[28%] ${ink}`}
          />
        ))}
        <motion.span
          animate={{ opacity: [1, 0.25, 1] }}
          transition={{ repeat: Infinity, duration: 1.1 }}
          className={`relative ml-[1%] h-[62%] w-[3.8%] rounded-full ${ink}`}
        >
          <span className={`absolute left-1/2 top-0 h-[13%] w-[320%] -translate-x-1/2 -translate-y-1/2 rounded-full ${ink}`} />
          <span className={`absolute bottom-0 left-1/2 h-[13%] w-[320%] -translate-x-1/2 translate-y-1/2 rounded-full ${ink}`} />
        </motion.span>
      </div>
    </div>
  );
}

function LogoLockup() {
  return (
    <div className="flex min-w-0 items-center gap-3">
      <LogoMark className="h-12 w-12 shrink-0 rounded-2xl" />
      <div className="truncate text-lg font-black tracking-[-0.005em] text-black sm:text-xl">Much Better Authenticator</div>
    </div>
  );
}

function Badge({ children, icon }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-black/10 bg-white px-4 py-2 text-sm font-black text-black shadow-sm shadow-black/5">
      {icon ? <Icon name={icon} className="h-4 w-4" /> : null}
      {children}
    </span>
  );
}

const features = [
  {
    icon: "keyboard",
    title: "Codes in your iOS keyboard",
    body: "Add the Much Better Authenticator keyboard once. Then tap any 2FA code from the bar above your keyboard and it lands at the cursor. Works in every app, no Full Access required, no clipboard touched.",
  },
  {
    icon: "chrome",
    title: "One click in Chrome",
    body: "The extension recognizes the site you're signing into, surfaces the matching code, and asks your iPhone for approval. FaceID accepts; the code inserts itself before the timer ticks.",
  },
  {
    icon: "shieldCheck",
    title: "New phone, same codes",
    body: "iCloud Keychain syncs your 2FA secrets across every Apple device you own, encrypted end-to-end by Apple. Restore on a new iPhone and your codes are already there. No transfer code, no QR re-scan.",
  },
  {
    icon: "zap",
    title: "Instant approval window",
    body: "Approve once with FaceID and the next two minutes of codes flow without prompts. The window resets on every interaction and ends the moment you put the app down.",
  },
];

const steps = [
  "Open any login page",
  "Click the account in Chrome",
  "FaceID on your iPhone",
  "Code lands at the cursor",
];

const proofPoints = [
  "Keyboard-native",
  "Chrome auto-fill",
  "iCloud Keychain sync",
  "Open source",
];

const securityFeatures = [
  {
    icon: "lock",
    title: "Hardware-backed Keychain",
    body: "Secrets live in the iOS Keychain, protected by the Secure Enclave. The keyboard reads them locally and has zero network capability.",
  },
  {
    icon: "shieldCheck",
    title: "Zero-knowledge relay",
    body: "The relay server forwards ciphertext between your phone and your browser. It cannot decrypt anything. Plaintext never touches our infrastructure.",
  },
  {
    icon: "code",
    title: "X25519 + ChaCha20-Poly1305",
    body: "Pairing derives a shared key on-device using elliptic-curve Diffie-Hellman. Messages are sealed with the same primitives that protect Signal and WireGuard.",
  },
  {
    icon: "cloud",
    title: "iCloud Keychain backup",
    body: "Sync uses Apple's end-to-end encryption, keys protected by your Apple ID and device passcode. Apple cannot read your 2FA secrets — by design.",
  },
  {
    icon: "faceid",
    title: "FaceID for every request",
    body: "Every code release requires biometric approval. The two-minute trust window is opt-in, time-bound, and resets the moment the app backgrounds.",
  },
  {
    icon: "puzzle",
    title: "Open source, end to end",
    body: "Every component is auditable: the iOS app, the keyboard, the Chrome extension, the relay server. Build it from source if you want to verify the build matches.",
  },
];

const comparisonRows = [
  { feature: "Codes inserted via the system keyboard", us: true, them: false },
  { feature: "One-click auto-fill in Chrome", us: true, them: false },
  { feature: "Phone migration without per-account re-enroll", us: true, them: false },
  { feature: "Source code public and auditable", us: true, them: false },
  { feature: "Domain-aware account routing", us: true, them: false },
  { feature: "Time-bound trust window after FaceID", us: true, them: false },
  { feature: "Cloud servers can read your codes", us: false, them: "Often" },
  { feature: "Requires a paid subscription", us: false, them: "Sometimes" },
];

const faqItems = [
  {
    q: "What happens if I lose my phone?",
    a: "If iCloud Keychain sync is on (it's a single toggle in Settings), every 2FA account syncs automatically to your other Apple devices and restores on a new iPhone the moment you sign into iCloud. No transfer code, no manual export, no contacting customer support for every service.",
  },
  {
    q: "Can the relay server read my codes?",
    a: "No. The relay only sees ciphertext. Encryption keys are derived during pairing using X25519 Diffie-Hellman and live exclusively on your iPhone and your browser. The relay forwards encrypted bytes between them and is mathematically incapable of decrypting anything.",
  },
  {
    q: "Does the iOS keyboard need \"Allow Full Access\"?",
    a: "No. Much Better Authenticator's keyboard works without Full Access. It reads codes locally from the iOS Keychain through the app group and has no network capability. The globe-icon switch in any keyboard is all you need.",
  },
  {
    q: "Which services work with this?",
    a: "Any service that supports time-based one-time passwords (TOTP) — the open standard. That's effectively every major site with 2FA: Google, Microsoft, GitHub, AWS, Stripe, Notion, Discord, banking apps, and thousands more.",
  },
  {
    q: "Can I import from Google Authenticator?",
    a: "Yes. Generate an export QR in Google Authenticator (Transfer accounts), scan it in Much Better Authenticator, and confirm which accounts to import. Multi-QR exports are handled automatically.",
  },
  {
    q: "Is it really free?",
    a: "Yes. No ads, no subscriptions, no upsells, no premium tier. The relay is operated as a public service with strictly no logging beyond ephemeral room state.",
  },
];

function runSmokeTests() {
  const failures = [];

  if (features.length !== 4) failures.push("Expected four feature cards.");
  if (steps.length !== 4) failures.push("Expected four flow steps.");
  if (proofPoints.length < 3) failures.push("Expected at least three proof points.");
  if (!features.every((feature) => feature.icon && feature.title && feature.body)) failures.push("Each feature needs icon, title, and body.");
  if (!steps.includes("Code lands at the cursor")) failures.push("Final flow step is missing.");
  if (!features.some((feature) => feature.icon === "chrome")) failures.push("Chrome extension feature is missing.");
  if (securityFeatures.length < 4) failures.push("Expected at least four security features.");
  if (comparisonRows.length < 4) failures.push("Expected at least four comparison rows.");
  if (faqItems.length < 4) failures.push("Expected at least four FAQ items.");

  return failures;
}

const smokeTestFailures = runSmokeTests();
if (smokeTestFailures.length > 0) {
  throw new Error(`Smoke tests failed: ${smokeTestFailures.join(" ")}`);
}

function CodeField({ code, compact = false }) {
  return (
    <div className={`flex items-center ${compact ? "gap-2" : "gap-3"}`}>
      {code.map((item, index) => (
        <motion.span
          key={`${item}-${index}`}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.35 + index * 0.08 }}
          className={`${compact ? "h-7 w-7 rounded-lg text-sm" : "h-12 w-12 rounded-xl text-2xl"} grid place-items-center bg-black font-black text-white`}
        >
          {item}
        </motion.span>
      ))}
      <motion.span
        animate={{ opacity: [1, 0.18, 1] }}
        transition={{ repeat: Infinity, duration: 1 }}
        className={`${compact ? "h-8 w-1" : "h-14 w-1.5"} ml-1 rounded-full bg-black`}
      />
    </div>
  );
}

function HeroVisual({ code }) {
  return (
    <motion.div initial={{ opacity: 0, y: 22 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.65, delay: 0.1 }} className="relative">
      <div className="absolute -right-4 -top-5 hidden h-28 w-28 rounded-full bg-black md:block" />
      <div className="absolute -bottom-7 -left-5 hidden h-20 w-20 rounded-full border-[18px] border-black md:block" />
      <div className="absolute right-12 top-16 hidden rounded-[1.6rem] border border-black/10 bg-white px-5 py-4 shadow-xl shadow-black/10 lg:block">
        <div className="flex items-center gap-3">
          <div className="grid h-9 w-9 place-items-center rounded-xl bg-black text-white">
            <Icon name="faceid" className="h-5 w-5" />
          </div>
          <div>
            <div className="text-xs font-black uppercase tracking-[0.18em] text-black/35">Approved</div>
            <div className="text-sm font-black">FaceID, 0.4s</div>
          </div>
        </div>
      </div>

      <div className="relative overflow-hidden rounded-[2.8rem] border border-black/10 bg-white p-5 shadow-2xl shadow-black/10">
        <div className="rounded-[2.25rem] bg-black p-5 text-white">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="h-3 w-3 rounded-full bg-white/35" />
              <span className="h-3 w-3 rounded-full bg-white/35" />
              <span className="h-3 w-3 rounded-full bg-white/35" />
            </div>
            <div className="rounded-full bg-white/10 px-3 py-1 text-xs font-bold text-white/65">login.example.com</div>
          </div>

          <div className="mt-12 rounded-[2rem] bg-white p-5 text-black sm:mt-16">
            <div className="flex items-center justify-between gap-4">
              <div>
                <div className="text-sm font-black uppercase tracking-[0.2em] text-black/35">Verification code</div>
                <div className="mt-1 text-sm font-bold text-black/45">Inserted from keyboard</div>
              </div>
              <div className="hidden items-center gap-2 rounded-full bg-[#f7f7f2] px-3 py-2 text-xs font-black sm:flex">
                <Icon name="lock" className="h-4 w-4" />
                Secure
              </div>
            </div>

            <div className="mt-5 rounded-[1.5rem] border-2 border-black px-4 py-4 sm:px-5">
              <CodeField code={code} />
            </div>
          </div>

          <div className="mt-5 rounded-[1.8rem] bg-white/10 p-4">
            <div className="flex items-center gap-3">
              <LogoMark className="h-14 w-14 shrink-0 rounded-2xl" inverted />
              <div className="min-w-0">
                <div className="truncate text-sm font-black">Much Better Authenticator</div>
                <div className="truncate text-sm text-white/55">Correct code found for this site</div>
              </div>
              <div className="ml-auto grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white text-black">
                <Icon name="check" className="h-5 w-5" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
}

function MigrationVisual() {
  return (
    <div className="relative grid items-center gap-6 rounded-[2.4rem] border border-black/10 bg-white p-6 shadow-sm shadow-black/5 sm:grid-cols-[1fr_auto_1fr_auto_1fr] sm:p-8">
      <div className="flex flex-col items-center gap-3 text-center">
        <div className="grid h-20 w-20 place-items-center rounded-3xl border border-black/10 bg-[#f7f7f2]">
          <Icon name="phone" className="h-10 w-10" />
        </div>
        <div className="text-sm font-black">Old iPhone</div>
        <div className="text-xs font-bold text-black/45">All your 2FA accounts</div>
      </div>

      <Icon name="arrowRight" className="hidden h-6 w-6 text-black/30 sm:block" />

      <div className="flex flex-col items-center gap-3 text-center">
        <div className="grid h-20 w-20 place-items-center rounded-3xl bg-black text-white">
          <Icon name="cloud" className="h-10 w-10" />
        </div>
        <div className="text-sm font-black">iCloud Keychain</div>
        <div className="text-xs font-bold text-black/45">End-to-end encrypted</div>
      </div>

      <Icon name="arrowRight" className="hidden h-6 w-6 text-black/30 sm:block" />

      <div className="flex flex-col items-center gap-3 text-center">
        <div className="grid h-20 w-20 place-items-center rounded-3xl border border-black/10 bg-[#f7f7f2]">
          <Icon name="phone" className="h-10 w-10" />
        </div>
        <div className="text-sm font-black">New iPhone</div>
        <div className="text-xs font-bold text-black/45">Codes already there</div>
      </div>
    </div>
  );
}

function FAQRow({ item, isOpen, onToggle }) {
  return (
    <div className="overflow-hidden rounded-[1.6rem] border border-black/10 bg-white shadow-sm shadow-black/5">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between gap-4 px-6 py-5 text-left transition hover:bg-black/[0.025]"
      >
        <span className="text-base font-black tracking-[-0.005em] sm:text-lg">{item.q}</span>
        <span className={`grid h-8 w-8 shrink-0 place-items-center rounded-full bg-black text-white transition ${isOpen ? "rotate-45" : ""}`}>
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={3} strokeLinecap="round">
            <path d="M12 5v14" />
            <path d="M5 12h14" />
          </svg>
        </span>
      </button>
      {isOpen ? (
        <div className="px-6 pb-6 text-base leading-7 text-black/68">
          {item.a}
        </div>
      ) : null}
    </div>
  );
}

export default function MuchBetterAuthenticatorLandingPage() {
  const [activeStep, setActiveStep] = useState(2);
  const [email, setEmail] = useState("");
  const [openFaq, setOpenFaq] = useState(0);
  const code = useMemo(() => ["4", "8", "1", "9", "2", "6"], []);

  function handleWaitlistSubmit(event) {
    event.preventDefault();
    if (!email) return;
    const subject = encodeURIComponent("Much Better Authenticator waitlist");
    const body = encodeURIComponent(`Email: ${email}\n\nLet me know when it's ready.`);
    window.location.href = `mailto:bhartiyashesh@gmail.com?subject=${subject}&body=${body}`;
  }

  return (
    <main className="min-h-screen overflow-hidden bg-[#f7f7f2] text-black antialiased" style={{ fontFamily: "Sora, Inter, ui-sans-serif, system-ui, sans-serif" }}>
      <div className="pointer-events-none fixed inset-0 opacity-[0.045]" style={{ backgroundImage: "linear-gradient(#000 1px, transparent 1px), linear-gradient(90deg, #000 1px, transparent 1px)", backgroundSize: "42px 42px" }} />
      <div className="pointer-events-none fixed left-1/2 top-0 h-[32rem] w-[32rem] -translate-x-1/2 rounded-full bg-white blur-3xl" />

      <section className="relative mx-auto flex max-w-7xl flex-col px-5 py-6 sm:px-8 lg:px-10">
        <nav className="flex items-center justify-between gap-4 rounded-[2rem] border border-black/10 bg-white/75 px-4 py-3 shadow-sm shadow-black/5 backdrop-blur-xl sm:px-5 sm:py-4">
          <LogoLockup />
          <div className="hidden items-center gap-8 text-sm font-semibold text-black/70 md:flex">
            <a href="#features" className="transition hover:text-black">Features</a>
            <a href="#migration" className="transition hover:text-black">Migration</a>
            <a href="#security" className="transition hover:text-black">Security</a>
            <a href="#faq" className="transition hover:text-black">FAQ</a>
          </div>
          <a href="#waitlist" className="shrink-0 rounded-full bg-black px-5 py-3 text-sm font-black text-white transition hover:-translate-y-0.5 hover:shadow-lg hover:shadow-black/15">
            Get access
          </a>
        </nav>

        <section className="grid items-center gap-12 py-16 md:grid-cols-[1.02fr_0.98fr] md:py-24">
          <motion.div initial={{ opacity: 0, y: 18 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.55 }}>
            <Badge icon="zap">Two-factor that's already there</Badge>

            <h1 className="mt-8 max-w-4xl text-6xl font-black leading-[0.95] tracking-[-0.025em] sm:text-7xl lg:text-[6.4rem]">
              2FA without the fumble.
            </h1>

            <p className="mt-8 max-w-2xl text-xl leading-8 text-black/68">
              Codes appear on your iOS keyboard and inside Chrome. Switch phones tomorrow and every account is already waiting, restored from iCloud Keychain without a single QR re-scan. Sign-in stops feeling like work.
            </p>

            <div className="mt-10 flex flex-col gap-3 sm:flex-row">
              <a href="#waitlist" className="group inline-flex items-center justify-center gap-2 rounded-full bg-black px-7 py-4 text-base font-black text-white transition hover:-translate-y-0.5 hover:shadow-xl hover:shadow-black/15">
                Join waitlist
                <Icon name="arrowRight" className="h-4 w-4 transition group-hover:translate-x-0.5" />
              </a>
              <a href="#flow" className="inline-flex items-center justify-center rounded-full border border-black/15 bg-white px-7 py-4 text-base font-black shadow-sm shadow-black/5 transition hover:-translate-y-0.5 hover:bg-[#f7f7f2]">
                See how it works
              </a>
            </div>

            <div className="mt-10 grid max-w-xl grid-cols-2 gap-3 sm:grid-cols-4">
              {proofPoints.map((point) => (
                <div key={point} className="rounded-[1.4rem] border border-black/10 bg-white px-4 py-3 text-center text-sm font-black text-black/60 shadow-sm shadow-black/5">
                  {point}
                </div>
              ))}
            </div>
          </motion.div>

          <HeroVisual code={code} />
        </section>
      </section>

      <section id="features" className="relative mx-auto max-w-7xl px-5 py-8 sm:px-8 lg:px-10">
        <div className="mb-6 flex items-end justify-between gap-6">
          <div>
            <div className="mb-3 text-sm font-black uppercase tracking-[0.22em] text-black/35">What changes</div>
            <h2 className="text-4xl font-black tracking-[-0.015em] sm:text-5xl">The code comes to you.</h2>
            <p className="mt-4 max-w-2xl text-lg leading-7 text-black/65">
              Every other authenticator makes you switch apps, memorize six digits, and race the timer. Much Better Authenticator removes the switch.
            </p>
          </div>
        </div>

        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {features.map((feature, index) => (
            <motion.div
              key={feature.title}
              initial={{ opacity: 0, y: 14 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.35 }}
              transition={{ duration: 0.45, delay: index * 0.06 }}
              className="group rounded-[2rem] border border-black/10 bg-white p-6 shadow-sm shadow-black/5 transition hover:-translate-y-1 hover:shadow-xl hover:shadow-black/10"
            >
              <div className="mb-6 grid h-12 w-12 place-items-center rounded-2xl bg-black text-white transition group-hover:rotate-3 group-hover:scale-105">
                <Icon name={feature.icon} className="h-6 w-6" />
              </div>
              <h3 className="text-xl font-black tracking-[-0.005em]">{feature.title}</h3>
              <p className="mt-3 leading-7 text-black/62">{feature.body}</p>
            </motion.div>
          ))}
        </div>
      </section>

      <section id="migration" className="relative mx-auto max-w-7xl px-5 py-20 sm:px-8 lg:px-10">
        <div className="grid items-start gap-10 md:grid-cols-[0.95fr_1.05fr]">
          <div>
            <div className="mb-4 inline-flex rounded-full bg-black px-4 py-2 text-sm font-black text-white">The phone problem, solved</div>
            <h2 className="text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-6xl">
              Phone change? You're already done.
            </h2>
            <p className="mt-6 text-lg leading-8 text-black/68">
              Most authenticators turn a lost or upgraded phone into a multi-day recovery project. You hunt for backup codes, contact every service one by one, sit on hold with banks. Much Better Authenticator never let that be the design.
            </p>
            <p className="mt-4 text-lg leading-8 text-black/68">
              Your 2FA secrets sync through iCloud Keychain with Apple's end-to-end encryption. Sign into iCloud on a new iPhone, open the app, and every account is already there — codes generating, the keyboard ready.
            </p>
            <ul className="mt-6 space-y-3 text-base leading-7 text-black/72">
              <li className="flex gap-3">
                <span className="mt-1 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-black text-white">
                  <Icon name="check" className="h-3 w-3" />
                </span>
                <span>No transfer activation code to chase down.</span>
              </li>
              <li className="flex gap-3">
                <span className="mt-1 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-black text-white">
                  <Icon name="check" className="h-3 w-3" />
                </span>
                <span>No per-account QR re-scan, no support tickets.</span>
              </li>
              <li className="flex gap-3">
                <span className="mt-1 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-black text-white">
                  <Icon name="check" className="h-3 w-3" />
                </span>
                <span>Restore happens through Apple — we never touch your secrets.</span>
              </li>
              <li className="flex gap-3">
                <span className="mt-1 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-black text-white">
                  <Icon name="check" className="h-3 w-3" />
                </span>
                <span>Same accounts on iPhone, iPad, and (soon) Mac, in sync.</span>
              </li>
            </ul>
          </div>

          <MigrationVisual />
        </div>
      </section>

      <section id="flow" className="relative mx-auto grid max-w-7xl gap-8 px-5 py-16 sm:px-8 md:grid-cols-[0.82fr_1.18fr] lg:px-10">
        <div>
          <div className="mb-5 inline-flex rounded-full bg-black px-4 py-2 text-sm font-black text-white">The flow</div>
          <h2 className="text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-6xl">
            Security stays. Friction leaves.
          </h2>
          <p className="mt-6 text-lg leading-8 text-black/65">
            Autocomplete for authentication: deliberate, visible, controlled, and much faster than hunting for a separate app. Every step is local and biometric-gated.
          </p>
          <div className="mt-8 rounded-[2rem] border border-black/10 bg-white p-4 shadow-sm shadow-black/5">
            <div className="rounded-[1.5rem] bg-[#f7f7f2] p-4">
              <div className="text-xs font-black uppercase tracking-[0.2em] text-black/35">Preview</div>
              <div className="mt-4 rounded-[1.25rem] bg-white p-4">
                <CodeField code={code} compact />
              </div>
            </div>
          </div>
        </div>

        <div className="rounded-[2.5rem] border border-black/10 bg-white p-4 shadow-xl shadow-black/5">
          <div className="grid gap-3">
            {steps.map((step, index) => (
              <button
                key={step}
                type="button"
                onClick={() => setActiveStep(index)}
                className={`flex items-center justify-between rounded-[1.6rem] px-5 py-5 text-left transition ${
                  activeStep === index ? "bg-black text-white shadow-lg shadow-black/15" : "bg-[#f7f7f2] text-black hover:bg-black/5"
                }`}
              >
                <span className="flex items-center gap-4">
                  <span className="grid h-10 w-10 place-items-center rounded-full bg-white text-sm font-black text-black">{index + 1}</span>
                  <span className="text-xl font-black tracking-[-0.005em]">{step}</span>
                </span>
                {activeStep === index ? <Icon name="zap" className="h-5 w-5" /> : null}
              </button>
            ))}
          </div>
        </div>
      </section>

      <section id="security" className="relative mx-auto max-w-7xl px-5 py-16 sm:px-8 lg:px-10">
        <div className="mb-10 max-w-3xl">
          <div className="mb-3 text-sm font-black uppercase tracking-[0.22em] text-black/35">Security</div>
          <h2 className="text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-6xl">
            Open primitives. Closed access.
          </h2>
          <p className="mt-6 text-lg leading-8 text-black/65">
            Every layer uses well-understood cryptography. Every layer is auditable. The relay is mathematically incapable of reading what flows through it.
          </p>
        </div>

        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {securityFeatures.map((item, index) => (
            <motion.div
              key={item.title}
              initial={{ opacity: 0, y: 12 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.4 }}
              transition={{ duration: 0.4, delay: index * 0.05 }}
              className="rounded-[1.8rem] border border-black/10 bg-white p-6 shadow-sm shadow-black/5"
            >
              <div className="mb-4 grid h-11 w-11 place-items-center rounded-xl bg-black text-white">
                <Icon name={item.icon} className="h-5 w-5" />
              </div>
              <h3 className="text-lg font-black tracking-[-0.005em]">{item.title}</h3>
              <p className="mt-3 leading-7 text-black/62">{item.body}</p>
            </motion.div>
          ))}
        </div>
      </section>

      <section className="relative mx-auto max-w-7xl px-5 py-16 sm:px-8 lg:px-10">
        <div className="mb-8 max-w-3xl">
          <div className="mb-3 text-sm font-black uppercase tracking-[0.22em] text-black/35">Built different</div>
          <h2 className="text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-6xl">
            What other authenticators don't do.
          </h2>
          <p className="mt-6 text-lg leading-8 text-black/65">
            A real comparison of capabilities. We left the columns honest.
          </p>
        </div>

        <div className="overflow-hidden rounded-[2.2rem] border border-black/10 bg-white shadow-sm shadow-black/5">
          <div className="grid grid-cols-[1.6fr_1fr_1fr] items-center gap-2 border-b border-black/10 bg-[#f7f7f2] px-6 py-4 text-xs font-black uppercase tracking-[0.18em] text-black/45 sm:gap-4 sm:px-8 sm:text-sm">
            <div>Capability</div>
            <div className="text-center text-black">Much Better Authenticator</div>
            <div className="text-center">Most authenticators</div>
          </div>
          {comparisonRows.map((row, idx) => (
            <div
              key={row.feature}
              className={`grid grid-cols-[1.6fr_1fr_1fr] items-center gap-2 px-6 py-4 sm:gap-4 sm:px-8 ${idx % 2 === 1 ? "bg-black/[0.02]" : ""}`}
            >
              <div className="text-sm font-bold sm:text-base">{row.feature}</div>
              <div className="text-center">
                {row.us === true ? (
                  <span className="inline-grid h-8 w-8 place-items-center rounded-full bg-black text-white">
                    <Icon name="check" className="h-4 w-4" />
                  </span>
                ) : row.us === false ? (
                  <span className="inline-grid h-8 w-8 place-items-center rounded-full border border-black/15 text-black/35">
                    <Icon name="xmark" className="h-4 w-4" />
                  </span>
                ) : (
                  <span className="text-sm font-black">{row.us}</span>
                )}
              </div>
              <div className="text-center">
                {row.them === true ? (
                  <span className="inline-grid h-8 w-8 place-items-center rounded-full bg-black/80 text-white">
                    <Icon name="check" className="h-4 w-4" />
                  </span>
                ) : row.them === false ? (
                  <span className="inline-grid h-8 w-8 place-items-center rounded-full border border-black/15 text-black/35">
                    <Icon name="xmark" className="h-4 w-4" />
                  </span>
                ) : (
                  <span className="text-sm font-black text-black/55">{row.them}</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="relative mx-auto max-w-7xl px-5 py-10 sm:px-8 lg:px-10">
        <div className="grid overflow-hidden rounded-[2.8rem] bg-black text-white shadow-2xl shadow-black/15 md:grid-cols-2">
          <div className="p-8 sm:p-12">
            <div className="mb-8 inline-flex rounded-full bg-white px-4 py-2 text-sm font-black text-black">Before / After</div>
            <h2 className="max-w-md text-5xl font-black leading-[1.02] tracking-[-0.02em]">Same security. Less chaos.</h2>
            <p className="mt-6 max-w-md text-base leading-7 text-white/68">
              Compare the everyday sign-in. The math is the same. The experience is not.
            </p>
          </div>
          <div className="grid gap-px bg-white/10 p-px md:grid-cols-2">
            <div className="bg-black p-8">
              <div className="mb-5 text-sm font-black uppercase tracking-[0.2em] text-white/35">Before</div>
              <ul className="space-y-4 text-lg font-bold text-white/72">
                <li>Open the authenticator app</li>
                <li>Find the right account in a long list</li>
                <li>Squint at six digits</li>
                <li>Switch back, type before they refresh</li>
              </ul>
            </div>
            <div className="bg-white p-8 text-black">
              <div className="mb-5 text-sm font-black uppercase tracking-[0.2em] text-black/35">After</div>
              <ul className="space-y-4 text-lg font-bold">
                <li>FaceID</li>
                <li>Code lands at the cursor</li>
                <li>Hands never leave the keyboard</li>
                <li>Sign-in takes under a second</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section id="faq" className="relative mx-auto max-w-3xl px-5 py-16 sm:px-8 lg:px-10">
        <div className="mb-8">
          <div className="mb-3 text-sm font-black uppercase tracking-[0.22em] text-black/35">Questions</div>
          <h2 className="text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-6xl">
            Things people ask.
          </h2>
        </div>
        <div className="grid gap-3">
          {faqItems.map((item, index) => (
            <FAQRow
              key={item.q}
              item={item}
              isOpen={openFaq === index}
              onToggle={() => setOpenFaq(openFaq === index ? -1 : index)}
            />
          ))}
        </div>
      </section>

      <section id="waitlist" className="relative mx-auto max-w-7xl px-5 py-16 sm:px-8 lg:px-10">
        <div className="relative overflow-hidden rounded-[3rem] border border-black/10 bg-white p-8 shadow-2xl shadow-black/10 sm:p-12">
          <div className="absolute -right-24 -top-24 h-56 w-56 rounded-full bg-black" />
          <div className="absolute -right-10 top-20 h-28 w-28 rounded-full bg-[#f7f7f2]" />
          <LogoMark className="mb-8 h-24 w-24 rounded-[2rem]" />
          <h2 className="relative max-w-3xl text-5xl font-black leading-[1.02] tracking-[-0.02em] sm:text-7xl">
            The authenticator that keeps up with you.
          </h2>
          <p className="relative mt-6 max-w-2xl text-lg leading-7 text-black/65">
            Join the waitlist. You'll get a quiet email when Much Better Authenticator opens up.
          </p>
          <form
            className="relative mt-10 flex max-w-2xl flex-col gap-3 sm:flex-row"
            onSubmit={handleWaitlistSubmit}
          >
            <input
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="min-h-14 flex-1 rounded-full border border-black/15 bg-[#f7f7f2] px-6 text-base font-bold outline-none transition placeholder:text-black/35 focus:border-black"
            />
            <button type="submit" className="min-h-14 rounded-full bg-black px-8 text-base font-black text-white transition hover:-translate-y-0.5 hover:shadow-xl hover:shadow-black/15">
              Request access
            </button>
          </form>
          <p className="relative mt-5 max-w-xl text-sm leading-6 text-black/50">
            No spam. One email when it ships. Reply to it if you want; a real human reads them.
          </p>
        </div>
      </section>

      <footer className="relative mx-auto flex max-w-7xl flex-col gap-6 px-5 pb-10 sm:px-8 md:flex-row md:items-center md:justify-between lg:px-10">
        <LogoLockup />
        <div className="flex flex-col gap-2 text-sm font-bold text-black/45 md:items-end md:text-right">
          <div className="flex flex-wrap gap-4 md:justify-end">
            <a href="/privacy" className="text-black/70 transition hover:text-black">Privacy</a>
            <a href="/support" className="text-black/70 transition hover:text-black">Support</a>
            <a href="mailto:bhartiyashesh@gmail.com" className="text-black/70 transition hover:text-black">Contact</a>
          </div>
          <div>
            Made by{" "}
            <a
              href="https://yasheshbharti.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-black/75 underline decoration-black/20 underline-offset-4 transition hover:text-black hover:decoration-black/60"
            >
              Yashesh Bharti
            </a>
          </div>
          <div>© 2026 Much Better Authenticator</div>
        </div>
      </footer>
    </main>
  );
}
