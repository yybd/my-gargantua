# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] - 2026-06-15

### Added

- **"Why?" affordance and plain-language reasons on failed rows.** Failed items now show a human-readable explanation (e.g. "needs the privileged helper", "file is in use") and a "Why?" link that opens the same reasoning sheet used during scanning.

- **Privileged-helper row in Permissions settings.** Settings → Permissions surfaces the helper's current status alongside Full Disk Access and Finder Automation, letting users grant approval before a clean hits a system-owned file.

- **npm and yarn cleanup support.** The Developer Tools panel now discovers and measures npm and yarn (classic) caches alongside pnpm and Go, with native preview and clean commands for each.

### Fixed

- **Competing AI call-to-action buttons suppressed.** When a deeper AI provider is configured, the "Enable AI" button and rule-based note no longer appear alongside "Explain deeper" — the two competing accents conflicted and the label was misleading when AI was already active.

- **AI Models scan list now syncs on retry.** Recovered items were pruned from the summary but lingered in the AI Models background list; the scan list now removes them in step with the summary.

- **Node-shim interpreter resolution for pnpm and other Node-managed tools.** GUI-launched tools like pnpm re-exec `node` from their shim directory; Gargantua now prepends that directory (and the resolved binary's own directory) to the child PATH so the interpreter resolves correctly under launchd's minimal environment.

- **AI one-shot runner no longer drops final stderr bytes.** The Claude and Codex runners now wait for both stdout and stderr to reach EOF before reading the process exit code, closing a race that intermittently produced empty stderr and spurious exit-7 failures.

## [0.4.1] - 2026-06-15

### Added

- **Keyboard shortcuts across every results surface.** A full shortcut set (⌘A/⇧⌘A/⌘I select, ⌘F filter, ⌘↩ clean, ⌘⌫ trash, ⌘R rescan, and more) is now discoverable through the menu bar; ⌘/ opens a cheat-sheet overlay so nothing stays hidden.
- **"Explain deeper" on demand.** Any scan result can be escalated to a richer prose explanation routed through your Anthropic API key or a locally installed Claude Code CLI — no extra API key required for the CLI path.
- **OpenAI-compatible Cloud provider.** The Cloud AI engine now accepts any OpenAI Chat Completions endpoint — OpenAI, OpenRouter, Groq, Together AI, or a local server — via a configurable base URL, with per-provider Keychain accounts.
- **Codex as a maintenance engine.** The Agent Run screen and scheduled audits can now be routed to a local Codex one-shot runner as an alternative to Claude Code.
- **Per-model Ollama cleanup.** Each Ollama model surfaces as its own candidate with a conservative reclaimable-size figure; deletion routes through the Ollama daemon so shared-blob GC stays safe.
- **Per-repo Hugging Face cache cleanup.** Every cached HF repo (model, dataset, space) appears as its own cleanup candidate sized by real blob bytes; repos with detached snapshots surface an additional "stale revisions" entry that frees only blobs no live ref still needs.
- **Individual model files for flat-file AI stores.** LM Studio, ComfyUI, SD-WebUI, and Pinokio now surface each model file as its own candidate — remove one checkpoint without wiping the whole store.

### Changed

- **Unified AI engine setup with per-job assignment matrix.** Configure your engines once (Template, MLX, Claude Code, Codex, Cloud), then assign one to each job — inline explanations, deeper explanations, organize, maintenance — instead of scattering the choice across features. The AI tab reads as an explicit numbered two-step flow with a consistent icon + label + control grid on every engine card.

### Fixed

- **Automation permission grant for signed builds.** Hardened-runtime builds were silently denied before the consent prompt could appear (missing Apple Events entitlement); the entitlement is now present, and a new Automation card in Settings lets existing users grant or repair the permission without re-running onboarding.
- **Destructive shortcuts gated while a text field is focused.** ⌘⌫ and ⇧⌘⌫ now probe the live AppKit first-responder in addition to the published `isEditingText` flag, so Move to Trash / Delete Permanently can never fire while a filter or search field is active.
- **No Keychain prompt just for opening AI settings.** Checking whether a cloud key exists no longer decrypts the secret, so the "allow access to your keychain" prompt is reserved for an actual cloud request rather than firing on the settings screen.

## [0.4.0] - 2026-06-13

### Added

- **User-authored cleanup rules.** Drop custom YAML rules into `~/Library/Application Support/Gargantua/rules/` and they load alongside bundled rules — they survive app updates, appear as a distinct category in the Rule Viewer, and are automatically clamped to `review` safety so a user rule can never be promoted to a destructive `safe` action.

### Fixed

- **Sparkle update notes pane.** The release notes panel no longer spins endlessly on the update prompt — notes are now correctly attached to each release asset and served at a resolvable URL.
- **Menu bar icon and label.** The menu bar now shows the Gargantua brand mark (with an alert dot when items are pending) and a dynamic label reflecting current alert state, replacing the generic system icon and static text.

## [0.3.0] - 2026-06-06

### Added

- **Quit-and-clean for blocked items.** Deep Clean surfaces items held by a running app with a Quit affordance instead of hiding them, so you can release and remove a cache without hunting down the app yourself.
- **Recoverable system cleanup.** The privileged helper can remove root-owned items from your own Trash (bounded), and routes removed system items to your Trash rather than root's, so deletions stay recoverable.
- **View-only items are clearly locked.** Items that can't be safely removed render as locked, non-selectable rows, with removability reconciled at scan time so they're excluded from cleanup up front.

### Changed

- **Stronger trust defaults.** Privileged items are floored at "review" rather than auto-approved, black-box profile-level safety overrides are gone, and the rules-directory override is gated to debug builds.
- **Version-aware privileged helper.** App updates reload the helper so elevated actions always run the current helper code.
- **Releases are smoke-tested.** The signed app is launched and verified before notarization so broken builds don't ship.

### Fixed

- **Scheduled scans register correctly.** The background-scan LaunchAgent no longer reports "not found"; `.notFound` is handled as SMAppService's normal pre-registration state and the agent registers as expected.
- **Browsers are left alone while running.** Browser cache/data rules are skipped when the browser is open, avoiding corruption of an active profile.
- **Scans skip mount points.** Mounted disk images and network/external volumes are never targeted.
- **Accurate image health.** Valid images are no longer flagged as corrupt when the file extension misreports the format.
- **Cleanup robustness.** Already-gone paths count as removed, transient removal failures retry, and delete failures are no longer mislabeled as missing Full Disk Access.

## [0.2.2] - 2026-06-05

### Added

- **Commercial licensing** (release builds only, via `GARGANTUA_LICENSING=1`). A 14-day trial fronts the destructive-action paths (Deep Clean execute, Smart Uninstaller scrub); scans and previews stay free forever. Licenses are sold one-time through [Polar.sh](https://polar.sh) and activated by pasting a key in `Settings → License` (or via the `gargantua://activate?key=...` deep link). Activation binds to the Mac (up to 3), validates against Polar's public customer-portal API, and is cached locally with a 14-day offline grace window. Source builds remain fully unlocked under AGPL-3.0.
- **Landing page** under `docs/site/` (static, ready for GitHub Pages) with the screenshot carousel, feature list, and Buy / Download-trial CTAs.

### Fixed

- **Launch crash in packaged builds.** GargantuaCore resources now resolve from the app bundle's `Contents/Resources` instead of SwiftPM's generated `Bundle.module`, whose baked lookup paths don't exist in a shipped `.app` and aborted the app on first render.
- **Privileged helper client authentication** now uses `setCodeSigningRequirement` (audit-token based), closing the PID-reuse race in the previous manual `SecCode` check.

### Changed

- **Release pipeline** builds from a clean git worktree checked out at the tag, so shipped artifacts always match the tagged commit.

## [0.1.3] - 2026-05-27

## [0.1.2] - 2026-05-27

## [0.1.1] - 2026-05-27

### Added

- **Sparkle 2 auto-updates** with EdDSA-signed appcasts, signed-feed enforcement, and stable/beta channels (`Settings → About`).
- **Privileged helper** (`GargantuaPrivilegedHelper`) registered via SMAppService and reached over XPC, used for elevated-trust uninstall paths so the app never invokes `sudo`.
- **Scheduled scans** backed by a `GargantuaScheduler` LaunchAgent registered through SMAppService, with interval presets, a custom 5-field cron expression, profile selection, and skip-on-battery (`Settings → Automation`).
- **MCP SSE transport** alongside stdio: bind localhost or LAN, bearer-token auth in Keychain, generate/rotate/revoke from `Settings → Network`.
- **Claude Code Agent** integration for non-interactive maintenance runs with read-only-by-default tools, per-session destructive-tool grants, and configurable model/turn limits.
- **Local MLX inference** with a self-built `mlx.metallib` colocated in the app bundle, idle-unload after 60 s, model staging under `~/Library/Application Support/Gargantua/Models/`.
- **Cloud AI (Anthropic)** with Keychain-only key storage, per-request redaction, optional 4 KB content-preview consent, hard monthly spend cap, and a dynamic Anthropic model picker.
- **Disk Explorer** treemap and directory drill-down for visualizing reclaimable space before cleaning.
- **AI Models** profile and view for downloaded LLM/diffusion model storage, biased toward `review`.
- **AI model intelligence** for review-only duplicate model candidates and orphan `.gguf` / `.safetensors` / `.onnx` / PyTorch-family weights, using filename/size metadata without reading model contents.
- **File Health** scans (empty files, big files, similar images, broken symlinks) backed by a vendored `czkawka_cli`.
- **Duplicate Finder** backed by a vendored `fclones`, scoped to user-defined personal-scope roots.
- **Command-action rules** schema (`Resources/command_rules/`) with starter coverage for `xcrun simctl delete unavailable`, `pnpm store prune`, `go clean -cache`, and opt-in `go clean -modcache`; surfaced through scan + cleanup.
- **Stale-version discovery** for review-gated Xcode DeviceSupport and JetBrains Toolbox version sets, using keep-latest retention, current-version hints, and pinned-path exclusions before surfacing old versions.
- **App-pack remnant rules** for Docker, Xcode, Android Studio, JetBrains, VS Code/Cursor/Zed, Unity/Unreal/Godot, and Raycast.
- **`pkgutil` receipt evidence** in Smart Uninstaller and the MCP `explain` tool: shows pkg ID, version, and install date as ownership provenance, never as deletion permission.
- **Protected-roots policy** (`safety_policy/protected_roots.yaml`) hard-blocking cleanup at filesystem roots regardless of rule classification, with user-extendable but bundled-immutable entries.
- **Menu bar widget** with optional launch-at-login via `SMAppService.loginItem`.
- **Audit trail** at `~/Library/Logs/Gargantua/audit.json` for every MCP-triggered cleanup attempt, with retention configurable in `Settings → About`.
- **Release pipeline**: `Scripts/release.sh` orchestrates build → assemble → strip → codesign → notarize app → DMG → notarize DMG → `spctl --assess` → signed Sparkle appcast.
- **Local publish flow**: `Scripts/publish.sh` runs the release pipeline and then uploads the DMG + `appcast.xml` to a GitHub Release and pushes `Casks/gargantua.rb` to `inceptyon-labs/homebrew-tap`.
- **Vendored helpers** built from source via `Scripts/fetch-vendored-bins.sh` (`fclones`, `czkawka_cli`); installation verified by `Scripts/smoke/verify-vendored-bins.sh`.
- **CI**: SwiftLint + `swift test --enable-code-coverage` with a 40% floor enforced by `Scripts/coverage-priorities.sh` on `macos-15`.
- **Mole rule parity expansion**: app cleanup coverage for cloud-sync, Office/mail, communication, virtualization, creative/media, productivity, launcher, game, utility, and remote desktop caches; Smart Uninstaller remnant templates for WebKit, HTTP storage, app scripts, plug-ins, XDG config, app extensions, system-level paths, and protected receipts.

### Changed

- Developer Tools now prefers structured Docker `system df --format json` previews when available,
  falls back to the legacy table output, and explains unknown post-run byte estimates instead of borrowing unrelated totals.
- Protected Developer Tools operations now carry stronger risk copy and safety styling; Docker volume prune and Docker system prune
  route through full-modal acknowledgment with explicit data-loss wording.
- Reviewed snapshot now ships **51 cleanup files / 287 rules**, **2 generic + 7 app-pack remnant files / 28 + 63 rules**, and **4 command-action rules**. See `docs/mole-rule-parity-audit.md` for what's deferred.
- Advanced command-action cleanup now has an opt-in `Advanced Commands` profile plus parser validation that requires review safety, affected roots outside protected roots, explicit consequence copy, a bounded timeout, and restore guidance before bundled advanced YAML can load.
- Smart Uninstaller now evaluates curated `app_pack` rules before broad generic remnant rules so app-specific review/protected classifications win during path dedupe.
- Synced the reviewed Mole-expanded rule snapshot to the public `gargantua-rules` repository.

### Fixed

- `MCP explain` no longer advertises a top-level `oneOf` schema, which broke Anthropic API tool registration.
- `NSHumanReadableCopyright` in `Info.plist` corrected to AGPL-3.0 (was incorrectly labelled MIT).

## [0.1.0] - 2026-04-23

### Added

- Initial public release.
- YAML-driven cleanup and uninstall rules (19 cleanup files / 83 rules, 2 uninstall files / 12 rules).
- MCP server (`GargantuaMCP`) with Phase 2 read-only tools (`scan`, `analyze`, `status`, `explain`, `list_profiles`) and Phase 3 destructive `clean` tool protected by protected-path hard-reject, 60s-per-client rate limit, audit trail, and cancel-notification grace period.
- Privileged helper (`GargantuaPrivilegedHelper`) for operations requiring elevated trust.
- Local AI explainability via MLX Swift for rule explanations: AI can explain a rule's safety classification but cannot lower it.
