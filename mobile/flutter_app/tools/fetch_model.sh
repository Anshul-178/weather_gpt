#!/usr/bin/env bash
# (Windows Git Bash: run with `bash tools/fetch_model.sh hf_...`)
# One-time fetch of the license-gated Gemma 3 1B GGUF model file.
#
# The app bundles whatever sits in assets/models/ — once this file is present,
# users never download anything: the model runs on-device via llama.cpp and
# installs from the APK on first use.
#
# Usage:
#   ./tools/fetch_model.sh hf_YOUR_TOKEN
#   HF_TOKEN=hf_YOUR_TOKEN ./tools/fetch_model.sh
#
# Prerequisite: accept the (free) Gemma license with the account that owns the
# token: https://huggingface.co/litert-community/Gemma3-1B-IT
set -euo pipefail

FILE="gemma-3-1b-it-Q4_K_M.gguf"
URL="https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/${FILE}"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/models"
DEST="${DEST_DIR}/${FILE}"

TOKEN="${1:-${HF_TOKEN:-}}"
if [ -z "${TOKEN}" ]; then
  echo "Error: pass a Hugging Face read token as \$1 or set HF_TOKEN." >&2
  echo "  1. Accept the license: https://huggingface.co/litert-community/Gemma3-1B-IT" >&2
  echo "  2. Create a read token: https://huggingface.co/settings/tokens" >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"

echo "Downloading ${FILE} (~769 MB) -> ${DEST}"
curl -L --fail --retry 3 -C - \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "User-Agent: weathergpt-fetch/1.0" \
  -o "${DEST}" "${URL}"

echo
echo "Done: ${DEST}"
echo "Next: run 'flutter pub get' and rebuild the app so the model is bundled."
