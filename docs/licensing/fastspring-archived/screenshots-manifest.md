# Screenshots manifest

What to capture for the FastSpring product page, the landing page, and the App Store-style press kit. Aim for **5–7 screenshots** in landscape orientation, **3840×2400** (Apple's "marketing 4K" — covers retina down to thumbnails cleanly).

Use the `app-store-screenshot-studio` skill (in `~/.claude/skills/`) to drive Xcode Build MCP for the captures, then Nano Banana Pro to add framing if you want App Store-style chrome. The skill knows the sizes and copy conventions.

## Required captures

| # | Screen | What it shows | Suggested caption |
|---|---|---|---|
| 1 | **Dashboard** | Triage roadmap with disk-usage gauge, next actions, reclaimable summary | "Glance the system. Pick where to dig in." |
| 2 | **Deep Clean — scan results** | Three-bucket grouping (safe / review / protected), AI explanations visible | "Every finding classified. Nothing destructive without confirmation." |
| 3 | **Smart Uninstaller — plan review** | An app being uninstalled with its leftovers grouped (bundle, preferences, caches, login items) | "Find every file an app leaves behind. Scrub them with the bundle." |
| 4 | **Dev Artifact Purge** | Multiple projects with size estimates, selective per-project keep/clear | "node_modules, target, DerivedData, Docker layers. Surgical, not blanket." |
| 5 | **File Organizer — rule-based** | Organization preview with AI-proposed moves, approve gate visible | "Rules-driven. Local-AI proposals you approve before any move happens." |
| 6 | **Settings → License** | The trial state (showing days remaining) OR the licensed state | "Open source. Pay for the notarized build and signed updates." |
| 7 | **Background Items** | Login items + launch agents audit with safety annotations | "Audit what's running on launch. Quarantine what doesn't belong." |

## Style notes

- All captures should use the **dark theme** (it's the only theme; this is the actual product).
- Window framing: include the title bar with traffic lights. Don't crop to content-only — the macOS chrome is the brand.
- Don't show real personal data. Use fixture content: `~/Demo/`, `~/Projects/sample/`, etc. Set up a separate macOS user (`gargantua-demo`) and shoot from there.
- The dock and menu bar should be **hidden** from captures. Use `defaults write com.apple.dock autohide -bool true && killall Dock` before shooting; restore after.
- **No FDA warning banner** in shots. Grant Full Disk Access to the demo user's Gargantua install before capturing so the banner doesn't appear.

## Capture command (Scripts/run.sh based)

```bash
# from the gargantua repo root, on the demo user account:
GARGANTUA_LICENSING=1 ./Scripts/run.sh &
# Wait for launch
sleep 8
# Use the app-store-screenshot-studio skill to drive the capture loop
# Output: docs/fastspring/screenshots/01-dashboard.png, 02-deep-clean.png, ...
```

## Logo asset

FastSpring wants a square logo, **1024×1024 transparent PNG**.

Source: `Sources/GargantuaCore/Resources/Brand/` — the accretion-disc brand mark. Export at 1024 from the existing asset. If the existing artwork isn't 1024-clean, regenerate via `nano-banana-pro` from a high-res source using the prompt:

> "Minimalist black hole accretion disc, orange-amber ring, dark void background, flat vector style, centered, transparent background, 1024×1024"

Save as `docs/fastspring/logo-1024.png`.
