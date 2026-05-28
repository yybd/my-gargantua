# FastSpring application & product setup

Prep materials and a step-by-step checklist for getting Gargantua live on FastSpring. See `gargantua-cfyg` (Phase 4 of the commercial-licensing parent bean) for the broader plan.

## Why FastSpring (recap)

Researched May 2026:
- **Merchant of Record** — handles VAT / EU sales tax for us
- **Built-in license-key fulfillment** (CocoaFob template) — no Keygen.sh bolt-on
- **Mac-app-friendly approvals** — CleanCocoa reference repo is canonical
- Fees: ~5.9% + $0.95
- Alternatives ranked: Paddle + Keygen.sh (cheaper but Paddle Billing dropped native keys, approval roulette), Lemon Squeezy (Stripe-migration limbo — avoid), Gumroad (10% — too expensive at scale)

## Before you apply

Have the following ready in a separate place (do **not** commit these to the repo):

- [ ] **Inceptyon Labs LLC EIN** (federal tax ID)
- [ ] **Business address** (Tampa, FL — the LLC address on file)
- [ ] **Business phone** (FastSpring may call to verify)
- [ ] **Business bank account** for payouts (account + routing number)
- [ ] **Driver's license / passport** scan (FastSpring KYC)
- [ ] **Email address** for the FastSpring admin account (recommend a dedicated one, not personal)

Public-facing material — these live in this directory and get pasted into the FastSpring forms:

- [`refund-policy.md`](refund-policy.md) — paste into the refund-policy field
- [`app-description.md`](app-description.md) — product description on the storefront
- [`feature-list.md`](feature-list.md) — bullet list for the product page
- [`screenshots-manifest.md`](screenshots-manifest.md) — what to capture + upload
- [`license-email-template.md`](license-email-template.md) — the email the customer gets post-purchase

## Application checklist

### 1. Submit application

- [ ] Sign up at https://fastspring.com (use the dedicated business email)
- [ ] Company name: **Inceptyon Labs LLC**
- [ ] Business type: **Limited Liability Company (LLC)**
- [ ] Country: **United States**, State: **Florida**
- [ ] Paste refund policy from `refund-policy.md`
- [ ] Paste app description from `app-description.md`
- [ ] Add Gargantua product website URL (your landing page — defer to Phase 5 if not live yet; can use the GitHub repo URL temporarily)
- [ ] Upload square logo (1024×1024 transparent PNG) — extract from `Sources/GargantuaCore/Resources/Brand/`
- [ ] Submit and wait. Reported approval time: **3–10 business days**. Plan around this.

### 2. Configure product (after approval)

- [ ] Create product: **Gargantua**, **$29 USD**, **one-time purchase**, **download**
- [ ] Enable **CocoaFob license-key fulfillment** (FastSpring built-in template)
- [ ] Click "Generate keypair" in FastSpring's dashboard — copies the **public key** to the binary, keeps the private key in FastSpring
- [ ] Set the **activation cap to 3** (FastSpring's "max activations per license" feature)
- [ ] Set the license-key email template from `license-email-template.md`
- [ ] Configure the post-purchase redirect URL to `gargantua://activate?key={license_key}` (deep-link to auto-activate the app)

### 3. Test purchase

- [ ] FastSpring supports a sandbox/test mode — use it for the first $0.50 charge
- [ ] Receive the license email at the test email address
- [ ] Paste the key into the Activate field in Gargantua's Settings → License pane
- [ ] Confirm: state flips to `.licensed`, chip disappears, destructive actions unlock

### 4. Hand off to Phase 5

Once the above is done, give yourself (or whoever drives Phase 5) the following values to swap into the code:

- [ ] **Production public key** (from FastSpring dashboard) → swap into `Sources/GargantuaLicensing/LicenseSigningKeys.swift` at the `// PHASE 4 SWAP:` marker
- [ ] **Checkout URL** (the FastSpring-hosted product page URL) → swap into `LicenseSettingsSection.openBuyURL()` and `DeepCleanView.openBuyURL()` — both currently point to `https://gargantua.dev/buy` placeholder
- [ ] **Restore-by-email API endpoint** (if FastSpring exposes one) — Phase 3's Restore button is currently stubbed; wire it in Phase 5
- [ ] **Webhook URL** (optional — only if we want server-side activation tracking; not required for the local-validation model)

## Fallback (if FastSpring rejects)

Researched but not preferred: **Paddle + Keygen.sh**.

- Paddle MoR: ~5% + $0.50, but Paddle Billing dropped native license-key generation (a regression from Paddle Classic).
- Keygen.sh bolt-on: ~$25/month for the licensing layer.
- Total: ~1% cheaper than FastSpring but $300/yr extra fixed cost + integration work.

Only pivot to this if FastSpring rejects approval (multiple indie reports of 3+ rejection cycles). If you go this path, the Phase 5 swap-in steps shift — Keygen issues the keys, Paddle handles checkout, two URLs change instead of one.

Lemon Squeezy is in Stripe-migration limbo as of 2026. Do not pivot here.
