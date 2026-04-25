#!/usr/bin/env bash
set -euo pipefail

IMAGE="runsplat:local-test"
VIDEO_URL="https://github.com/alx/runsplat/releases/download/v0.1.5/lighthouse.mp4"
STEPS=500          # low count so the test finishes in a few minutes
TIMEOUT=600        # seconds

# ── flags ──────────────────────────────────────────────────────────────────────
NO_BUILD=0
for arg in "$@"; do
  case $arg in
    --no-build) NO_BUILD=1 ;;
    *) echo "Usage: $0 [--no-build]"; exit 1 ;;
  esac
done

# ── helpers ────────────────────────────────────────────────────────────────────
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

# ── GPU check ─────────────────────────────────────────────────────────────────
if ! docker info 2>/dev/null | grep -q "nvidia"; then
  echo "WARNING: nvidia runtime not listed in 'docker info'."
  echo "  Run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
fi

# ── build ─────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $NO_BUILD -eq 0 ]]; then
  echo "Building $IMAGE ..."
  docker build -t "$IMAGE" "$REPO_ROOT"
else
  echo "Skipping build (--no-build)"
fi

# ── run handler with test input ───────────────────────────────────────────────
echo ""
echo "Running test job (steps=$STEPS, timeout=${TIMEOUT}s) ..."

TEST_INPUT=$(printf '{"input":{"video_url":"%s","steps":%d}}' "$VIDEO_URL" "$STEPS")

TMPLOG=$(mktemp)
trap 'rm -f "$TMPLOG"' EXIT

timeout "$TIMEOUT" docker run --rm --gpus all \
  "$IMAGE" \
  python3 handler.py --test_input "$TEST_INPUT" 2>&1 | tee "$TMPLOG" || {
  fail "Container exited non-zero or timed out after ${TIMEOUT}s"
}

# ── validate output ───────────────────────────────────────────────────────────
# Grep the log file directly — avoids echo pipeline issues with multi-MB output.
if ! grep -q "completed successfully" "$TMPLOG"; then
  fail "Did not find 'completed successfully' in output"
fi

# Confirm ply_base64 has a non-trivial value (match ≥50 base64 chars after the key).
PLY_SAMPLE=$(grep -o "'ply_base64': '[A-Za-z0-9+/=]\{50,\}'" "$TMPLOG" | head -c 80 || true)

if [[ -z "$PLY_SAMPLE" ]]; then
  fail "ply_base64 is empty or suspiciously small"
fi

echo ""
pass "Job completed successfully, ply_base64 present"
