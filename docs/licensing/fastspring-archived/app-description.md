# Product description

For the FastSpring product page (and re-usable for the future landing page at gargantua.dev). Three lengths so you can paste the right one wherever it fits.

---

## One-liner (≤80 chars)

Native macOS cleaner for developers and power users. Open source, optional license.

## Short (≤300 chars — App Store style)

Gargantua scans your Mac for reclaimable space, surfaces what's actually safe to remove, and lets you act with confidence. Built for developers and power users who want full disk access — not a sandbox cleaner. Open source under AGPL-3.0. A license unlocks notarized auto-updating builds.

## Long (~600 words — product page)

Most Mac cleaners ship as sandboxed App Store apps. The sandbox blocks them from where the actual clutter lives — `~/Library/Caches`, `~/Library/Application Support`, the leftover files apps leave behind when you drag them to the Trash, the Docker overlay directories, the dev artifact piles in `node_modules` and `.gradle` and `target` and `.swiftpm`.

**Gargantua isn't sandboxed.** It runs as a full-disk-access Mac app for developers and power users who want a cleaner that can actually see and reach the disk.

### What it does

- **Triage scan** — A lightweight first pass that surfaces obvious cleanup candidates: caches, logs, temp files, installer leftovers, abandoned app bundles. Most users free 3–8 GB on the first triage alone.
- **Deep Clean** — A rule-based deep scan against a curated YAML rule set. Each finding tagged with a safety classification: safe / review / protected. The default profile excludes anything that could cost you work.
- **Smart Uninstaller** — When you uninstall an app, Gargantua finds every file the app left behind (preferences, caches, application support, login items, launch agents, helpers) and offers to scrub them with the bundle.
- **Duplicate Finder** — Powered by `fclones` (the fastest open-source duplicate scanner). Reports reclaimable bytes accurately — N copies of an X-byte file is (N-1)×X reclaimable, not N×X.
- **Dev Artifact Purge** — Targeted at developers. Identifies and clears `node_modules`, `target/`, `.gradle/`, build outputs, Docker layer caches, Xcode DerivedData, iOS Simulator runtimes. You pick which projects to keep.
- **File Health** — Watches for orphaned files, broken symlinks, files in the wrong places.
- **File Organizer** — Sort files by rules. Optional local AI model proposes organization plans you approve before any move happens.
- **Background Items** — Audit launch agents, daemons, and login items. Identify what's running and why.

### Safety

Every destructive action goes through an explicit confirmation. Protected roots (your home directory, `/System`, `/Applications`, `/Library`) are off-limits by default — overrides require explicit confirmation per scan.

Local AI explanations (powered by a 1.2B MLX model) help you understand *why* a file was flagged before you delete it. Cloud AI (optional, Anthropic-only, you supply the key) handles harder cases.

### Open source

Gargantua is **AGPL-3.0** on GitHub: https://github.com/inceptyon-labs/gargantua

You can clone, audit, build, and run a fully unlocked version for free. The source build is exactly the product — no feature gating, no "Pro" version.

### What you're buying

A **license** unlocks:
- A **notarized, signed, auto-updating** binary you don't have to build yourself
- **Sparkle-based delta updates** for future versions
- **Support via email** (`support@inceptyon.com`)
- **Funding the open-source development** that keeps the source build viable

A single license activates Gargantua on **up to 3 Macs**. **$29 one-time** — no subscription.

A 14-day trial is built in. Scans and previews stay free forever; destructive actions unlock during trial and require a license after 14 days.

### Built by

Gargantua is built by [Inceptyon Labs](https://github.com/inceptyon-labs), a one-person indie studio in Tampa, Florida. Source on GitHub. Issues and contributions welcome.
