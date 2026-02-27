#!/bin/bash
# Usage: eval-task2.sh <model> <YYYY-MM>
# Note: tflint --init requires outbound access to sigstore.dev and GitHub.
#       If running in a network-restricted environment, the tflint step will be skipped (0 points).
set -e

MODEL=$1
YYYYMM=$2
TF_DIR="benchmark/reports/${YYYYMM}/artifacts/${MODEL}/task2/terraform"
SCORE_FILE="benchmark/reports/${YYYYMM}/artifacts/${MODEL}/task2/score.json"

python3 benchmark/scripts/extract-tf-files.py \
  "benchmark/reports/${YYYYMM}/artifacts/${MODEL}/task2/output.md" \
  "${TF_DIR}"

score=0

terraform fmt -check -recursive "${TF_DIR}" && score=$((score+1)) || true
(cd "${TF_DIR}" && terraform init && terraform validate) && score=$((score+1)) || true
(cd "${TF_DIR}" && cp /workspace/benchmark/.tflint.hcl . && tflint --init && tflint -f compact) \
  && score=$((score+1)) || true
checkov -d "${TF_DIR}" --framework terraform && score=$((score+1)) || true

echo "{\"task2_score\": ${score}, \"max\": 4}" > "${SCORE_FILE}"
echo "Task2 score: ${score}/4"
