#!/usr/bin/env bash
# Test the colmap-serverless image locally.
# Requires ../../../colmap-serverless to be checked out, OR the image already built.
set -euo pipefail

IMAGE="colmap-serverless:local-test"
COLMAP_REPO="${COLMAP_REPO:-$HOME/code/colmap-serverless}"
VIDEO_URL="https://github.com/alx/runsplat/releases/download/v0.1.5/lighthouse.mp4"
NUM_FRAMES=30
TIMEOUT=900

# ── flags ──────────────────────────────────────────────────────────────────────
NO_BUILD=0
for arg in "$@"; do
  case $arg in
    --no-build) NO_BUILD=1 ;;
    *) echo "Usage: $0 [--no-build]"; exit 1 ;;
  esac
done

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

if ! docker info 2>/dev/null | grep -q "nvidia"; then
  echo "WARNING: nvidia runtime not listed in 'docker info'."
fi

if [[ $NO_BUILD -eq 0 ]]; then
  if [[ ! -d "$COLMAP_REPO" ]]; then
    fail "colmap-serverless repo not found at $COLMAP_REPO. Clone it or set COLMAP_REPO env var."
  fi
  echo "Building $IMAGE from $COLMAP_REPO ..."
  docker build -t "$IMAGE" "$COLMAP_REPO"
else
  echo "Skipping build (--no-build)"
fi

echo ""
echo "Running colmap test job (num_frames=$NUM_FRAMES, timeout=${TIMEOUT}s) ..."

TEST_INPUT=$(printf '{"input":{"video_url":"%s","num_frames":%d,"matching":"sequential","gpu":true}}' \
  "$VIDEO_URL" "$NUM_FRAMES")

TMPLOG=$(mktemp)
trap 'rm -f "$TMPLOG"' EXIT

timeout "$TIMEOUT" docker run --rm --gpus all \
  "$IMAGE" \
  python3 handler.py --test_input "$TEST_INPUT" 2>&1 | tee "$TMPLOG" || {
  fail "Container exited non-zero or timed out after ${TIMEOUT}s"
}

if ! grep -q "completed successfully" "$TMPLOG"; then
  fail "Did not find 'completed successfully' in output"
fi
if ! grep -q "'colmap_workspace_b64':" "$TMPLOG"; then
  fail "colmap_workspace_b64 key not found in output"
fi

LOGSIZE=$(wc -c < "$TMPLOG")
if [[ "$LOGSIZE" -lt 50000 ]]; then
  fail "Output suspiciously small (${LOGSIZE} bytes)"
fi

echo ""
pass "COLMAP job completed, colmap_workspace_b64 present (${LOGSIZE} bytes)"
