# Plan B — Polar.sh

If FastSpring drags past 72 hours or rejects activation, here's the pivot.

## Why Polar

- **Self-serve signup** — instant dashboard access, no sales gate
- **Merchant of Record** — VAT/EU sales tax handled, single payout
- **5% + $0.50** standard rate (Early Member 4% + $0.40 window closed May 27, 2026)
- **Built-in license keys** with their own API + UI
- **Indie-flavored brand** — designed for the "monetize many products" use case, which fits the Inceptyon Labs portfolio plan
- **No CocoaFob/DSA deprecation traps** — their licensing is HTTP-API-based, not crypto-suite-locked

## Cost of pivoting

**Code-side rewrite is non-trivial.** Polar does NOT use AquaticPrime plists.

- License keys are UUID-style strings issued by Polar at sale time
- Validation = HTTP POST to `polar.sh/api/v1/license-keys/validate` with the key
- Requires internet for activation and (optionally) periodic re-validation
- Loses offline-after-activation UX that AquaticPrime gives us

**Files that change if you pivot:**

- `Sources/GargantuaLicensing/LicenseStore.swift` — replace SecKey RSA verification with `URLSession` POST to Polar's validation endpoint. Cache validation result locally with short TTL (1-24 hours) so brief offline periods don't lock the user out.
- `Sources/GargantuaLicensing/LicenseReceipt.swift` — slim to `{keyString: String, customerEmail: String, customerName: String, lastValidated: Date}`. No signature bytes, no plist canonicalization.
- `Sources/GargantuaLicensing/LicenseSigningKeys.swift` — **delete**. Embedded RSA public key is moot under API validation.
- `Sources/GargantuaCore/Views/Licensing/LicenseSettingsSection.swift` — file picker reverts to a paste-key TextField. Smaller UI surface.
- `Sources/GargantuaCore/Views/Licensing/UnlockGargantuaSheet.swift` — same.
- `Tests/GargantuaLicensingTests/` — mostly delete + rewrite around mocking Polar's API. Roughly 2/3 of the AquaticPrime tests become irrelevant.
- `Scripts/dev-issue-license.sh` — **delete**. Polar issues real keys at any point via their dashboard's "issue test key" button.

Net: about a day of code work + 4–6 hours of UX/QA. Less code than the AquaticPrime rewrite added, since most of the cryptography we built becomes irrelevant.

## Signup checklist (when you decide to pivot)

### 1. Create the account

- [ ] https://polar.sh → Sign up with `support@inceptyon.io`
- [ ] Connect Stripe Connect account (Polar uses Stripe under the hood for processing)
- [ ] Add Inceptyon Labs LLC business details — EIN, address, banking
- [ ] Set up an organization called `inceptyon-labs` (matches GitHub org for brand consistency)

### 2. Create the Gargantua product

- [ ] Products → New Product → "Gargantua"
- [ ] Pricing: $29 USD, one-time
- [ ] Description: paste from `app-description.md` (long version)
- [ ] Feature list: paste from `feature-list.md`
- [ ] Refund policy: paste from `refund-policy.md`
- [ ] Upload screenshots from `screenshots-manifest.md`

### 3. Enable license key benefit

- [ ] Add Benefit → "License Keys"
- [ ] Format: UUID v4 (Polar's default; no reason to pick another)
- [ ] Activations per key: 3 (matches the 3-Mac cap we picked for FastSpring)
- [ ] Activation TTL: 24 hours (how long a validated state stays cached client-side before we re-check)
- [ ] Expiration: never (one-time purchase, license never expires)

### 4. Test purchase

- [ ] Polar has a test mode toggle — flip it on
- [ ] Run a $0.50 charge with a test card
- [ ] Receive license key in confirmation email
- [ ] Switch to dev build of Gargantua (after the code pivot lands)
- [ ] Paste key into Settings → License → Activate
- [ ] Confirm activation hits Polar's API and unlocks destructive actions

### 5. Hand off to Phase 5

- [ ] Provide Polar's **product URL** (checkout link) → swap into `LicenseSettingsSection.openBuyURL()` and `DeepCleanView.openBuyURL()`
- [ ] Provide Polar's **validation endpoint** → wire into `LicenseStore` (likely `https://api.polar.sh/v1/license-keys/validate`)
- [ ] Generate an organization-scoped **API token** in Polar's dashboard → embed in `LicenseSigningKeys.swift` (or rename to `LicensePolarConfig.swift`) as a read-only key used to make validation calls. Note: this exposes the token in the binary — Polar's license-key validation endpoint is read-only by design, so this is the documented pattern.

## When NOT to pivot

If FastSpring activates within 72 hours, **stay on FastSpring**. The AquaticPrime work is done, tested, and shipping. Don't redo it for a marginally better brand.

The only scenarios that justify the pivot:
- FastSpring rejects activation outright
- FastSpring goes silent past 5 business days
- FastSpring quotes fees materially higher than the published ~5.9% + $0.95 (rare but reported)
- You realize you actually want to ship 3+ products in the next 6 months and want them all under one Polar org (FastSpring would require separate product configurations but works fine; Polar is just nicer for it)

## Don't run both at the same time

Two MoR storefronts for the same product fragments your tax records and confuses customers. Pick one, commit, hand the other a polite "withdrawing for now" email.
