#!/bin/bash
set -e

YYYYMM=$(date +'%Y-%m')
OUT_DIR="benchmark/reports/${YYYYMM}/artifacts/codex"
mkdir -p "${OUT_DIR}/task1" "${OUT_DIR}/task2" "${OUT_DIR}/task3"

echo "=== Task1: 設計 ==="
codex exec --output-last-message "${OUT_DIR}/task1/output.md" \
  "$(cat benchmark/prompts/task1-design.md)"

echo "=== Task2: コード生成 ==="
codex exec --output-last-message "${OUT_DIR}/task2/output.md" \
  "$(cat benchmark/prompts/task2-codegen.md)"

echo "=== Task3: レビュー ==="
codex exec --output-last-message "${OUT_DIR}/task3/output.md" \
  "$(cat benchmark/prompts/task3-review.md)"

echo "Done. Artifacts saved to ${OUT_DIR}"
