#!/bin/bash
# Usage: evaluate.sh <YYYY-MM>
set -e

YYYYMM=$1
REPORT_DIR="benchmark/reports/${YYYYMM}"

python3 benchmark/scripts/randomize-ab.py "${REPORT_DIR}"

A_MODEL=$(python3 -c "import json; print(json.load(open('${REPORT_DIR}/ab-mapping.json'))['A'])")
B_MODEL=$(python3 -c "import json; print(json.load(open('${REPORT_DIR}/ab-mapping.json'))['B'])")

EVAL_PROMPT=$(cat benchmark/prompts/eval-prompt.md)

for TASK in task1 task2 task3; do
  A_OUTPUT=$(cat "${REPORT_DIR}/artifacts/${A_MODEL}/${TASK}/output.md")
  B_OUTPUT=$(cat "${REPORT_DIR}/artifacts/${B_MODEL}/${TASK}/output.md")

  FULL_PROMPT="${EVAL_PROMPT}

## 成果物A

${A_OUTPUT}

## 成果物B

${B_OUTPUT}"

  echo "=== ${TASK}: Claude Code が評価 ==="
  claude -p "${FULL_PROMPT}" > "${REPORT_DIR}/artifacts/eval-by-claude-${TASK}.md"

  echo "=== ${TASK}: Codex が評価 ==="
  codex exec --output-last-message "${REPORT_DIR}/artifacts/eval-by-codex-${TASK}.md" \
    "${FULL_PROMPT}"
done

echo "Done. Evaluation saved to ${REPORT_DIR}/artifacts/"
