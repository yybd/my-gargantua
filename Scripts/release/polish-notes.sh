#!/usr/bin/env bash
# polish-notes.sh — produce polished release notes for a version.
#
# git-cliff builds a deterministic draft from the Conventional Commits since the
# last tag, then `claude -p` rewrites it into summarized, user-facing Keep a
# Changelog prose (bold lead-ins, benefit-focused sentences, related commits
# merged, internal noise dropped). Falls back to the raw git-cliff draft when
# claude is unavailable or the call fails. Prints the markdown section to stdout.
#
# Usage: polish-notes.sh <tag>           e.g. polish-notes.sh v0.4.0
# Env:   RELEASE_NOTES_MODEL (default: sonnet)
#        RELEASE_NOTES_AI=0 to skip the AI polish and emit the git-cliff draft

set -euo pipefail

TAG="${1:?usage: polish-notes.sh <tag, e.g. v0.4.0>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
MODEL="${RELEASE_NOTES_MODEL:-sonnet}"

# Deterministic draft (drop git-cliff's header preamble — we only want the body).
DRAFT="$(git cliff --unreleased --tag "$TAG" 2>/dev/null | awk 'f{print} /^## \[/{f=1; print}')"

# No AI, no claude, or an empty draft → emit the deterministic draft as-is.
if [ "${RELEASE_NOTES_AI:-1}" = "0" ] || ! command -v claude >/dev/null 2>&1 || [ -z "${DRAFT//[[:space:]]/}" ]; then
    printf '%s\n' "$DRAFT"
    exit 0
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
COMMITS="$(git log --pretty='- %s%n%b' "${LAST_TAG:+$LAST_TAG..}HEAD" 2>/dev/null)"

PROMPT="You are writing the release notes for Gargantua, a native macOS cleaner for developers and power users. Below is a deterministic draft (from git-cliff) and the raw commit log since the last release.

Rewrite into a polished Keep a Changelog section. Rules:
- Keep the exact heading line from the draft (## [x.y.z] - date).
- Group entries under ### Added / ### Changed / ### Fixed / ### Security as appropriate.
- Each entry: a bold lead-in phrase, then one user-facing sentence on the benefit or impact. Example: '- **Quit-and-clean for blocked items.** Deep Clean surfaces items held by a running app with a Quit affordance instead of hiding them.'
- Merge related commits into one entry, drop noise (pure refactors, internal tooling, CI), and never invent anything not present in the commits.
- Output ONLY the markdown section. No preamble, no commentary, no code fences.

=== git-cliff draft ===
${DRAFT}

=== raw commits ===
${COMMITS}"

OUT="$(printf '%s' "$PROMPT" | claude -p --model "$MODEL" 2>/dev/null || true)"
# Strip any stray code fences the model may add.
OUT="$(printf '%s\n' "$OUT" | sed '/^```/d')"

if [ -z "${OUT//[[:space:]]/}" ]; then
    printf '%s\n' "$DRAFT"   # AI failed/empty — fall back to the draft.
else
    printf '%s\n' "$OUT"
fi
