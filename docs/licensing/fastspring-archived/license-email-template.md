# License-key email template

The email FastSpring sends to a customer after purchase. Paste into the FastSpring email template configuration. Plain text — no HTML chrome. Mac-app indie convention.

---

**Subject:** Your Gargantua license

**Body:**

```
Hi {{customer.first_name}},

Thanks for buying Gargantua. Your license is below.

LICENSE KEY:
{{license_key}}

To activate:

1. Open Gargantua → Settings → License
2. Paste the key above into the "Activate" field
3. Click Activate

Or just click this link to auto-activate (only works if Gargantua is already installed):

  gargantua://activate?key={{license_key | url_encode}}

A single license activates on up to 3 Macs. To move it to a new Mac, deactivate on an old one first (Settings → License → Deactivate).

If activation fails or you have any other issue, reply to this email.

Source: https://github.com/inceptyon-labs/gargantua  (AGPL-3.0)
Refund policy: 30 days, no questions asked. Email support@inceptyon.com.

— Jason
Inceptyon Labs
```

## Notes

- `{{customer.first_name}}` / `{{license_key}}` are FastSpring's template variables (Liquid syntax) — adjust to whatever FastSpring's product email engine uses. Check their docs at activation time.
- `{{license_key | url_encode}}` — needed because the key is base64url and may contain characters that need URL-escaping when the customer clicks the auto-activate link.
- The deep-link path `gargantua://activate?key=...` is wired in `Sources/Gargantua/GargantuaApp.swift` (Phase 5 task to register the URL scheme in Info.plist if not already).
- Keep it plain text. HTML email gets stripped by many clients and Gmail flags overly-styled marketing emails as Promotions. Plain text lands in the inbox.
