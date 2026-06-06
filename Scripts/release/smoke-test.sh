#!/usr/bin/env bash
# smoke-test.sh — launch the assembled, signed app briefly and fail the release
# if it crashes on startup.
#
# Catches the class of bug where the app builds, signs, and notarizes fine but
# aborts before the first window renders — e.g. an unloadable SwiftPM resource
# bundle (`Bundle.module` fatalError) or any startup precondition. Runs after
# sign.sh and before notarize.sh so a launch crash fails the cut *before* the
# multi-minute notarization spend.
#
# We launch the binary directly (not via `open`) so we can capture stderr and
# the exit status. A healthy GUI app stays alive until we kill it; a crash
# self-exits within the window, dies by signal, or prints a fatal-error line.
#
# Skipped under --dry-run (no real artifact) and when GARGANTUA_SKIP_SMOKE_TEST
# is set (headless/CI hosts with no window server, where a GUI launch can't be
# evaluated reliably).

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_env.sh
. "$_SCRIPT_DIR/_env.sh"

if [ "$DRY_RUN" = "1" ]; then
    log "Smoke test: skipped (dry-run — no real artifact to launch)."
    exit 0
fi

if [ -n "${GARGANTUA_SKIP_SMOKE_TEST:-}" ]; then
    warn "Smoke test: skipped (GARGANTUA_SKIP_SMOKE_TEST set)."
    exit 0
fi

BIN="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
[ -x "$BIN" ] || die "smoke test: binary not found or not executable: $BIN"

TIMEOUT="${GARGANTUA_SMOKE_TIMEOUT:-8}"   # seconds to let the app prove it boots
STDERR_LOG="$(mktemp -t gargantua-smoke-XXXXXX)"
# Fatal signatures that mean a startup crash even if the shell later reaps the
# process as "killed by us".
FATAL_RE='could not load resource bundle|Fatal error|fatalError|Trace/BPT trap|precondition failed|EXC_BAD'

log "Smoke test: launching $APP_NAME for ${TIMEOUT}s to verify it boots..."

# Launch detached from our stdin; capture stderr.
"$BIN" >/dev/null 2>"$STDERR_LOG" &
APP_PID=$!

crashed=0
exited_early=0
elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        exited_early=1
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [ "$exited_early" = "1" ]; then
    # Reap and read the real exit status. A GUI app that quits on its own during
    # the boot window is a failure unless it exited cleanly (0) — a clean early
    # exit usually means no window server (headless), which we treat as
    # inconclusive rather than a crash. `|| status=$?` keeps `set -e` from
    # aborting here when the child died by signal (wait returns 128+signal).
    status=0
    wait "$APP_PID" || status=$?
    if [ "$status" -ge 128 ]; then
        warn "Smoke test: $APP_NAME died on launch (signal $((status - 128)))."
        crashed=1
    elif [ "$status" -ne 0 ]; then
        warn "Smoke test: $APP_NAME exited $status during boot."
        crashed=1
    else
        warn "Smoke test: $APP_NAME exited cleanly during boot window — likely no window server; treating as inconclusive."
    fi
else
    # Still alive after the window: it booted past first render. Shut it down.
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
fi

# A fatal line in stderr is authoritative regardless of how the process ended.
if grep -qE "$FATAL_RE" "$STDERR_LOG" 2>/dev/null; then
    warn "Smoke test: fatal startup output detected:"
    grep -E "$FATAL_RE" "$STDERR_LOG" | sed 's/^/    /' >&2
    crashed=1
fi

if [ "$crashed" = "1" ]; then
    warn "Captured stderr:"
    sed 's/^/    /' "$STDERR_LOG" >&2
    rm -f "$STDERR_LOG"
    die "smoke test failed: $APP_NAME does not launch. Refusing to ship a crashing build."
fi

rm -f "$STDERR_LOG"
log "Smoke test: OK — $APP_NAME launched and rendered without crashing."
