# FastSpring activation request email

Paste-ready email to send to FastSpring's sales/onboarding team when they put account activation behind a "talk to us first" gate. Tight, factual, signals that you're a real indie with the product already set up — not someone fishing.

## Where to send

Their onboarding contact path varies; try in order:
1. The "talk to sales" / "contact us" link from the signup gate page (usually pre-fills the right form)
2. `sales@fastspring.com`
3. Their support widget in the dashboard if you can get past the gate to a logged-in state

## Subject

```
Account activation — Inceptyon Labs LLC / Gargantua ($29 macOS app)
```

## Body

```
Hi FastSpring team,

I'm a solo indie developer at Inceptyon Labs LLC (Tampa, Florida) and I'd
like to activate my FastSpring account so I can start selling.

Product: Gargantua — a native macOS cleaner ($29 USD, one-time purchase,
downloadable software). Source is open under AGPL-3.0; the paid product is
the signed/notarized binary with Sparkle auto-updates. Repo:
https://github.com/inceptyon-labs/gargantua

I've already done the product-side setup in your dashboard:
- AquaticPrime license generator configured (RSA-2048 keypair, customer
  email + name fields in the plist content template)
- Filename template: #{key['Name']}.gargantualicense
- License delivery via email post-purchase

The app side is also wired:
- Production RSA public key embedded in the binary
- License file picker in Settings → License pane (NSOpenPanel)
- SecKey RSA-PKCS1v15-SHA1 verification against the embedded public key
- 14-day trial fronted by a license gate before any destructive action

The only thing I'm blocked on is account activation so I can run a test
charge in sandbox mode and confirm end-to-end delivery before going live.

Standard merchant details:
- Business: Inceptyon Labs LLC
- Country: United States
- State: Florida
- Business type: LLC
- EIN and banking info: ready to provide when needed
- Refund policy: 30 days, no questions
- Volume estimate: low at launch — Mac indie app, first product

Please let me know what you need from me to get activated, or if there's
a self-serve path I missed. Happy to hop on a quick call if that's faster
than email back-and-forth.

Thanks,
Jason Newberg
jason@inceptyon.io
support@inceptyon.io
```

## Tone notes — why this works

- **Opens with the ask + company name** so they don't need to scroll
- **One sentence on the product** — they sell to thousands of devs; they don't need a pitch deck
- **Receipts that you've done the dashboard work** signal you're past tire-kicking
- **Spelled-out merchant details** save them a follow-up email
- **Volume honesty** — claiming high volume on a $29 indie app at launch reads as fake; "low at launch" reads as real and matches their underwriting expectations
- **"Quick call" offer** is the unlock if email replies are slow — most onboarding ops would rather kill it in a 10-minute call than three days of email tag

## After you send

- Expected reply window: 24–72 hours
- If silent past 72 hours: ping the same thread once with "any update?" and start the Polar.sh signup in parallel — see `fallback-polar.md`
