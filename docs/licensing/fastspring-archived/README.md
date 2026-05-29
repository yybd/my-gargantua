# FastSpring application & product setup

Step-by-step checklist for getting Gargantua live on FastSpring with **AquaticPrime** license generation. See `gargantua-cfyg` (Phase 4 of the commercial-licensing parent bean) for the broader plan.

## What we're using and why

- **FastSpring** — Merchant of Record, handles VAT / EU sales tax, ~5.9% + $0.95 per transaction.
- **AquaticPrime license generator** — RSA-2048 + SHA-1, plist-based, modern macOS verification via `SecKey`. (We tried CocoaFob first; Apple removed DSA from `SecKey` so CocoaFob is dead for macOS 14+ apps. AquaticPrime is the surviving FastSpring preset that works on modern Mac.)
- **No formal approval gate** — FastSpring 2026 lets you straight into the dashboard. Verification happens at first transaction / payout. Skip the old "wait for approval" step.

## Before you apply

Have the following ready in a separate place (do **not** commit these to the repo):

- [ ] **Inceptyon Labs LLC EIN** (federal tax ID)
- [ ] **Business address** (Tampa, FL — the LLC address on file)
- [ ] **Business phone** (FastSpring may call to verify)
- [ ] **Business bank account** for payouts (account + routing number)
- [ ] **Driver's license / passport** scan (FastSpring KYC, requested at payout time)
- [ ] **Email address** for the FastSpring admin account (recommend `support@inceptyon.io` or a dedicated one)

Public-facing material — these live in this directory and get pasted into FastSpring's product page:

- [`refund-policy.md`](refund-policy.md) — paste into the refund-policy field
- [`app-description.md`](app-description.md) — product description on the storefront
- [`feature-list.md`](feature-list.md) — bullet list for the product page
- [`screenshots-manifest.md`](screenshots-manifest.md) — what to capture + upload
- [`license-email-template.md`](license-email-template.md) — the email the customer gets post-purchase

## Step-by-step

### 1. Sign up

- [ ] Sign up at https://fastspring.com (the trial form — "Sign up for free")
- [ ] What do you sell: **Downloadable Software**
- [ ] Annual revenue range: pick yours
- [ ] Work email: e.g. `support@inceptyon.io`
- [ ] Company name: **Inceptyon Labs LLC**
- [ ] Product website: `https://github.com/inceptyon-labs/gargantua` (or your landing page if live)

You're now in the dashboard. No approval gate to wait for.

### 2. Create the AquaticPrime license generator

- [ ] Dashboard → product → Fulfillment → Add Fulfillment → **Generate a License** → Choose Generator → **AquaticPrime**
- [ ] Product Name: `Gargantua`
- [ ] Full License Filename: `#{key['Name']}.gargantualicense`
- [ ] Public Key: paste contents of the RSA-2048 public key PEM
- [ ] Private Key: paste contents of the RSA-2048 private key PEM (traditional `BEGIN RSA PRIVATE KEY` format)
- [ ] License File → Content table — keep the default Product/Order/Timestamp rows; add custom rows:
  - `Name` = `#{name}`
  - `Email` = `#{email}`
  - Leave Custom 3–6 empty
- [ ] License Name dropdown: **Customizable Name**
- [ ] Save

### 3. Configure product

- [ ] Create product: **Gargantua**, **$29 USD**, **one-time purchase**, **download**
- [ ] Associate the AquaticPrime generator above with the product (drag-and-drop or "Add Fulfillment" on the product page — should already be wired if you created the generator from the product context)
- [ ] Set the post-purchase redirect URL to `gargantua://activate` (deep-link to open the app; Phase 5 wires the URL scheme handler)

### 4. Test purchase

- [ ] FastSpring supports a sandbox/test mode — use it for the first $0.50 charge
- [ ] Receive the license email at the test email address with the `.gargantualicense` plist file attached
- [ ] Open Gargantua → Settings → License → Open license file… → pick the downloaded file
- [ ] Confirm: state flips to `.licensed`, trial chip disappears, destructive actions unlock

### 5. Hand off to Phase 5

Once steps 1–4 work end-to-end, give yourself (or whoever drives Phase 5) the following to swap into the code:

- [ ] **Checkout URL** (the FastSpring-hosted product page URL) → swap into `LicenseSettingsSection.openBuyURL()` and `DeepCleanView.openBuyURL()` — both currently point to `https://gargantua.dev/buy` placeholder
- [ ] **Webhook URL** (optional — only if we want server-side activation tracking; not required for the local-validation model)
- [ ] **Production public key**: already embedded in `Sources/GargantuaLicensing/LicenseSigningKeys.swift`. Re-check it matches the public key FastSpring stored — if you regenerated keys at any point, swap the base64 DER string in that file.

## Why not CocoaFob

We initially planned CocoaFob (FastSpring's other Mac-app preset). It uses DSA-1024 signing. Apple removed DSA from `SecKey` in macOS 14+ — `SecKeyCreateWithData` with `kSecAttrKeyTypeDSA` fails with error -50, and `SecKeyRawVerify` (the legacy alternative) is unreachable from modern Swift. CleanCocoa's reference implementation no longer compiles cleanly on macOS 14. AquaticPrime uses RSA which modern macOS fully supports.

## Why not Pre-defined List

FastSpring's Pre-defined List option (pre-generate N keys, FastSpring assigns one per sale) doesn't bind keys to specific customers — anonymous, transferable keys. Bad fit for a paid product.

## Why not Remote Server Request

Would require us to host a server with the private key. Workable (Cloudflare Workers) but adds infrastructure we don't otherwise need.

## Fallback if AquaticPrime breaks

If something blocks the AquaticPrime path that we don't know about yet, the next move is **Remote Server Request**: deploy a tiny Cloudflare Worker that takes customer info from FastSpring, signs with our ECDSA P-256 key (kept secret in Worker secrets), and returns the license string. Reverts to the original Phase 2/3 wire format (base64url JSON). ~50 lines of TS, ~$0/mo on Workers free tier.
