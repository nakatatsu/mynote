#!/bin/bash
set -e

YYYYMM=$(date +'%Y-%m')
OUT_DIR="benchmark/reports/${YYYYMM}/artifacts/claude"
mkdir -p "${OUT_DIR}/task1" "${OUT_DIR}/task2" "${OUT_DIR}/task3"

echo "=== Task1: 設計 ==="
claude -p "$(cat benchmark/prompts/task1-design.md)" \
  > "${OUT_DIR}/task1/output.md"

echo "=== Task2: コード生成 ==="
claude -p "$(cat benchmark/prompts/task2-codegen.md)" \
  > "${OUT_DIR}/task2/output.md"

echo "=== Task3: レビュー ==="
claude -p "$(cat benchmark/prompts/task3-review.md)" \
  > "${OUT_DIR}/task3/output.md"

echo "Done. Artifacts saved to ${OUT_DIR}"
