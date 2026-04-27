#!/usr/bin/env bash
# Test a deployed RunPod serverless endpoint.
# Usage: ./scripts/test_runpod.sh <ENDPOINT_ID>
#        ENDPOINT_ID env var also accepted as fallback.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

VIDEO_URL="https://github.com/alx/runsplat/releases/download/v0.1.5/lighthouse.mp4"
STEPS=5000
POLL_INTERVAL=15   # seconds between status checks
TIMEOUT=660        # slightly over tests.json 600s timeout
OUTPUT_PLY="./output_test.ply"

# ── helpers ────────────────────────────────────────────────────────────────────
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# ── endpoint id ───────────────────────────────────────────────────────────────
ENDPOINT_ID="${1:-${ENDPOINT_ID:-}}"
if [[ -z "$ENDPOINT_ID" ]]; then
  fail "Usage: $0 <ENDPOINT_ID>  (or set ENDPOINT_ID env var)"
fi

# ── api key from .env ─────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env not found at $ENV_FILE"
fi
RUNPOD_API_KEY="$(grep -E '^RUNPOD_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
if [[ -z "$RUNPOD_API_KEY" ]]; then
  fail "RUNPOD_API_KEY not found in $ENV_FILE"
fi

BASE_URL="https://api.runpod.io/v2/${ENDPOINT_ID}"
AUTH_HEADER="Authorization: Bearer ${RUNPOD_API_KEY}"

# ── submit job ────────────────────────────────────────────────────────────────
echo "Submitting job to endpoint ${ENDPOINT_ID} (steps=${STEPS}) ..."
SUBMIT_PAYLOAD=$(printf '{"input":{"video_url":"%s","steps":%d}}' "$VIDEO_URL" "$STEPS")

SUBMIT_RESP=$(curl -sf -X POST "${BASE_URL}/run" \
  -H "Content-Type: application/json" \
  -H "${AUTH_HEADER}" \
  -d "$SUBMIT_PAYLOAD")

JOB_ID=$(echo "$SUBMIT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
if [[ -z "$JOB_ID" ]]; then
  fail "Failed to extract job ID from response: $SUBMIT_RESP"
fi
echo "Job submitted: $JOB_ID"

# ── poll for completion ───────────────────────────────────────────────────────
START_TIME=$(date +%s)
while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    fail "Timed out after ${TIMEOUT}s waiting for job $JOB_ID"
  fi

  STATUS_RESP=$(curl -sf "${BASE_URL}/status/${JOB_ID}" \
    -H "${AUTH_HEADER}")

  STATUS=$(echo "$STATUS_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))")
  echo "[${ELAPSED}s] Status: $STATUS"

  case "$STATUS" in
    COMPLETED)
      break
      ;;
    FAILED|CANCELLED)
      ERROR=$(echo "$STATUS_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('error') or d.get('output', {}).get('error') or '(no error field)')
" 2>/dev/null || echo "(could not parse error)")
      fail "Job $JOB_ID ended with status $STATUS: $ERROR"
      ;;
    IN_QUEUE|IN_PROGRESS)
      sleep "$POLL_INTERVAL"
      ;;
    *)
      echo "  Unknown status '$STATUS', continuing to poll..."
      sleep "$POLL_INTERVAL"
      ;;
  esac
done

# ── validate output ───────────────────────────────────────────────────────────
RESP_SIZE=${#STATUS_RESP}
if [[ $RESP_SIZE -lt 100000 ]]; then
  fail "Response suspiciously small (${RESP_SIZE} bytes) — ply_base64 value likely empty"
fi

if ! echo "$STATUS_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'ply_base64' in d.get('output', {}), 'ply_base64 not in output'
" 2>/dev/null; then
  fail "ply_base64 key not found in output"
fi

# ── decode and save ply ───────────────────────────────────────────────────────
echo "Decoding and saving PLY to $OUTPUT_PLY ..."
echo "$STATUS_RESP" | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
data = base64.b64decode(d['output']['ply_base64'])
with open('$OUTPUT_PLY', 'wb') as f:
    f.write(data)
print(f'Saved {len(data):,} bytes')
"

echo ""
pass "Job $JOB_ID completed — PLY saved to $OUTPUT_PLY"
