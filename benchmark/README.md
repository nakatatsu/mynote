# Benchmark

Claude Code vs Codex の月次IaCベンチマーク。

## 実行手順

### 2. タスク実行

```bash
# リポジトリルートから実行
bash benchmark/scripts/run-claude.sh
bash benchmark/scripts/run-codex.sh
```

成果物: `benchmark/reports/YYYY-MM/artifacts/{claude,codex}/task{1,2,3}/output.md`

### 3. タスク2 自動採点

```bash
bash benchmark/scripts/eval-task2.sh claude 2026-02
bash benchmark/scripts/eval-task2.sh codex  2026-02
```

### 4. 相互ブラインド評価 & レポート生成

```bash
bash benchmark/scripts/evaluate.sh 2026-02
python3 benchmark/scripts/generate-report.py benchmark/reports/2026-02
```

結果: `benchmark/reports/2026-02/result.md`

### 5. コミット

```bash
git add benchmark/reports/2026-02/
git commit -m "benchmark: add 2026-02 results"
```

## タスク定義・採点基準

- タスク定義: `benchmark/plan.md`
- 採点基準: `benchmark/scoring/`
