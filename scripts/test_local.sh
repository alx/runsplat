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
if ! docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 \
       nvidia-smi -L &>/dev/null; then
  fail "No GPU visible to Docker. Install nvidia-container-toolkit and retry."
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
RESULT=$(echo "$OUTPUT" | grep -o '{"ply_base64":.*}' | tail -1 || true)

if [[ -z "$RESULT" ]]; then
  fail "No JSON result found in output"
fi

STATUS=$(echo "$RESULT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || true)
PLY_LEN=$(echo "$RESULT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(len(d.get('ply_base64','')))" 2>/dev/null || true)

if [[ "$STATUS" != "done" ]]; then
  fail "status='$STATUS' (expected 'done')"
fi

if [[ -z "$PLY_LEN" || "$PLY_LEN" -lt 100 ]]; then
  fail "ply_base64 is empty or suspiciously small (len=$PLY_LEN)"
fi

echo ""
pass "status=done, ply_base64 length=$PLY_LEN bytes"
