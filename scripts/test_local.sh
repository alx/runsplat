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

OUTPUT=$(timeout "$TIMEOUT" docker run --rm --gpus all \
  "$IMAGE" \
  python3 handler.py --test_input "$TEST_INPUT" 2>&1) || {
  echo "$OUTPUT"
  fail "Container exited non-zero or timed out after ${TIMEOUT}s"
}

echo "$OUTPUT"

# ── validate output ───────────────────────────────────────────────────────────
# The RunPod SDK logs results as Python repr (single quotes), not JSON.
# Check for the SDK's own success line and presence of a non-trivial ply_base64.
if ! echo "$OUTPUT" | grep -q "completed successfully"; then
  fail "Did not find 'completed successfully' in output"
fi

PLY_LEN=$(echo "$OUTPUT" | grep -o "'ply_base64': '[^']*'" | head -1 | wc -c || true)

if [[ -z "$PLY_LEN" || "$PLY_LEN" -lt 100 ]]; then
  fail "ply_base64 is empty or suspiciously small"
fi

echo ""
pass "Job completed successfully, ply_base64 present (~${PLY_LEN} chars sampled)"
