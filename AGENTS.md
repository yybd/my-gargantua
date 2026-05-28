# Gargantua

> Tool-agnostic project guidance. Read by any AGENTS.md-compatible agent.

Gargantua is a native macOS cleaner for developers and power users.

## Dual-build pattern (open-source ↔ commercial)

Source is AGPL-3.0. `swift build` from a clean clone produces an unlocked binary. Release CI sets `GARGANTUA_LICENSING=1` to compile in the trial clock, license gate, and FastSpring activation paths.

- `Sources/GargantuaLicensing/` — the gated module. Public API is always defined; `#if GARGANTUA_LICENSING` switches between source-build and licensed behavior internally so call sites don't need conditional code.
- `Package.swift` — reads the env var via `Context.environment` and applies `.define("GARGANTUA_LICENSING")` to the `GargantuaLicensing` target only.
- `Scripts/release/build.sh` — exports `GARGANTUA_LICENSING=1` before invoking `swift build`.

When editing code that touches destructive actions (Deep Clean execute, Uninstaller scrub, Quarantine apply), route through `LicenseGate.shared.canExecuteDestructiveAction()` rather than `#if`-gating call sites directly.
