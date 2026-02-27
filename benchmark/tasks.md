# Benchmark 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Claude Code vs Codex の月次IaCベンチマークを、GHAでIssue作成・DevContainerでローカル実行・自動評価・レポート生成まで動かす

**Architecture:** GHAが月次でIssueを作成（リマインダー）。作業者がDevContainer内でシェルスクリプトを手動実行し Claude Code / Codex に3タスクを実行させ成果物を保存。タスク2は terraform/tflint/checkov で自動スコアリング。相互ブラインド評価後にresult.mdをコミット。

**Tech Stack:** GitHub Actions（Issue作成のみ）, Claude Code (`claude -p`), Codex CLI (`codex exec`), Terraform 1.14, tflint 0.61, checkov 3.2

---

## Task 1: プロンプトファイル作成

**Files:**
- Create: `benchmark/prompts/task1-design.md`
- Create: `benchmark/prompts/task2-codegen.md`
- Create: `benchmark/prompts/task3-review.md`
- Create: `benchmark/prompts/eval-prompt.md`

**Step 1: task1-design.md を作成**

plan.mdのタスク1定義をそのままモデルへの指示形式に変換する。
出力形式（ディレクトリ構成・モジュール分割・変数/出力・state管理）を明示すること。

**Step 2: task2-codegen.md を作成**

plan.mdのタスク2定義をモデルへの指示形式に変換する。
`main.tf / variables.tf / outputs.tf / versions.tf` の4ファイル構成で出力するよう明示する。
各ファイルの内容をコードブロック（` ```hcl:ファイル名 ` ）形式で出力させること（後工程での抽出に使う）。

**Step 3: task3-review.md を作成**

plan.mdのタスク3定義をモデルへの指示形式に変換する。
`[CRITICAL|HIGH|MEDIUM|LOW] <対象> : <問題> -> <改善案>` フォーマットと TOP3 列挙を必須とすること。
レビュー対象コードをプロンプト内にそのまま埋め込む。

**Step 4: eval-prompt.md を作成**

以下の構造で作成する:
- 「あなたはIaCコードレビュアーです。以下の成果物AとBを評価してください。どちらがどのAIが作ったかは不明です。」
- 評価軸: 正確性・安全性・可読性・Terraformベストプラクティス準拠
- 各軸を★5段階で評価し、総合コメントを記述する形式
- 「A/Bどちらが優れているか」の最終判定も含める

**Step 5: Commit**

```bash
git add benchmark/prompts/
git commit -m "feat: add benchmark prompt files"
```

---

## Task 2: 採点基準ファイル作成（Issueには含めない）

**Files:**
- Create: `benchmark/scoring/task1-rubric.md`
- Create: `benchmark/scoring/task2-scoring.md`
- Create: `benchmark/scoring/task3-answer-key.md`

**Step 1: task1-rubric.md を作成**

plan.mdの「採点用チェックリスト10項目」をそのまま記載する。
各項目を○/×で判定できる基準文にすること。

**Step 2: task2-scoring.md を作成**

plan.mdの「自動評価項目（/4点）」をそのまま記載する。
各ツールが1点ずつであることを明記する:
- terraform fmt: 1点
- terraform init && terraform validate: 1点
- tflint: 1点
- checkov: 1点

**Step 3: task3-answer-key.md を作成**

plan.mdの「仕込んだ問題点と正解重大度」表をそのまま記載する。
採点手順（指摘ヒット判定の基準、TOP3採点方法）も付記する。

**Step 4: Commit**

```bash
git add benchmark/scoring/
git commit -m "feat: add benchmark scoring rubrics"
```

---

## Task 3: DevContainerにCodex CLIを追加 ✅ 完了済み

`Dockerfile.local` / `versions.env` / `devcontainer.json` への追加は実施済み（`CODEX_VERSION=0.106`）。
DevContainer再ビルド後に `codex --version` で動作確認すること。

---

## Task 4: GHA - 月次Issue作成ワークフロー

**Files:**
- Create: `.github/workflows/benchmark-monthly-issue.yml`
- Create: `.github/issue-templates/benchmark-monthly.md`

**Step 1: Issue本文テンプレートを作成**

`.github/issue-templates/benchmark-monthly.md` に以下を記載:
- タイトル: `[Benchmark] YYYY-MM 月次実施`
- 本文: 各タスクのお題（plan.mdのタスク1〜3の「お題」セクション）
- チェックリスト:
  - [ ] Claude Code タスク1完了
  - [ ] Claude Code タスク2完了
  - [ ] Claude Code タスク3完了
  - [ ] Codex タスク1完了
  - [ ] Codex タスク2完了
  - [ ] Codex タスク3完了
  - [ ] 相互評価完了
  - [ ] result.md コミット完了
- ラベル: `benchmark`

**Step 2: ワークフローを作成**

```yaml
name: Benchmark Monthly Issue

on:
  schedule:
    - cron: '0 0 1 * *'
  workflow_dispatch:

jobs:
  create-issue:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/checkout@v4
      - name: Get current month
        id: date
        run: echo "yyyymm=$(date +'%Y-%m')" >> $GITHUB_OUTPUT
      - name: Create benchmark issue
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const body = fs.readFileSync('.github/issue-templates/benchmark-monthly.md', 'utf8')
              .replace(/YYYY-MM/g, '${{ steps.date.outputs.yyyymm }}');
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `[Benchmark] ${{ steps.date.outputs.yyyymm }} 月次実施`,
              body,
              labels: ['benchmark']
            });
```

**Step 3: Commit**

```bash
git add .github/workflows/benchmark-monthly-issue.yml .github/issue-templates/
git commit -m "feat: add benchmark monthly issue workflow"
```

---

## Task 5: ローカル実行スクリプト - Claude Code

**Files:**
- Create: `benchmark/scripts/run-claude.sh`

**Step 1: run-claude.sh を作成**

DevContainer内で実行する。3タスクを順番に実行し、成果物を保存する。

```bash
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
```

**Step 2: 実行権限を付与**

```bash
chmod +x benchmark/scripts/run-claude.sh
```

**Step 3: Commit**

```bash
git add benchmark/scripts/run-claude.sh
git commit -m "feat: add Claude Code local runner script"
```

---

## Task 6: ローカル実行スクリプト - Codex

**Files:**
- Create: `benchmark/scripts/run-codex.sh`

**Step 1: run-codex.sh を作成**

Task 5 と同構造で `codex exec` を使用する。

```bash
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
```

※ `codex exec` の正確なオプション名は実装時に `codex exec --help` で確認すること。

**Step 2: 実行権限を付与**

```bash
chmod +x benchmark/scripts/run-codex.sh
```

**Step 3: Commit**

```bash
git add benchmark/scripts/run-codex.sh
git commit -m "feat: add Codex local runner script"
```

---

## Task 7: タスク2 自動評価スクリプト

**Files:**
- Create: `benchmark/scripts/extract-tf-files.py`
- Create: `benchmark/scripts/eval-task2.sh`
- Create: `benchmark/.tflint.hcl`

**Step 1: ⚠️ tflint --init の挙動を事前検証してから実装する**

DevContainerで以下を実行し、AWSpluginが正常に取得できるか確認する:

```bash
mkdir /tmp/tflint-test && cd /tmp/tflint-test
cat > .tflint.hcl <<'EOF'
plugin "aws" {
  enabled = true
  version = "0.38.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
EOF
tflint --init
```

問題なければ `benchmark/.tflint.hcl` に同内容を記載する。

**Step 2: extract-tf-files.py を作成**

モデル出力のMarkdownから ` ```hcl:ファイル名 ` 形式のコードブロックを抽出し、
指定ディレクトリにファイルとして書き出すスクリプト。

```python
#!/usr/bin/env python3
"""Extract HCL code blocks from markdown output."""
import re, sys, os
from pathlib import Path

def extract(input_file: str, output_dir: str) -> None:
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    text = Path(input_file).read_text()
    pattern = re.compile(r'```hcl:(\S+)\n(.*?)```', re.DOTALL)
    for match in pattern.finditer(text):
        filename, content = match.group(1), match.group(2)
        (Path(output_dir) / filename).write_text(content)
        print(f"Extracted: {filename}")

if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
```

**Step 3: eval-task2.sh を作成**

```bash
#!/bin/bash
# Usage: eval-task2.sh <model> <YYYY-MM>
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
```

**Step 4: Commit**

```bash
git add benchmark/scripts/extract-tf-files.py \
        benchmark/scripts/eval-task2.sh \
        benchmark/.tflint.hcl
git commit -m "feat: add task2 auto-evaluation scripts"
```

---

## Task 8: 相互ブラインド評価 & レポート生成スクリプト

**Files:**
- Create: `benchmark/scripts/randomize-ab.py`
- Create: `benchmark/scripts/evaluate.sh`
- Create: `benchmark/scripts/generate-report.py`

**Step 1: randomize-ab.py を作成**

Claude/Codexの成果物をランダムにA/Bに割り当て、`ab-mapping.json` に保存する。

```python
#!/usr/bin/env python3
import random, json, sys
from pathlib import Path

def randomize(report_dir: str) -> None:
    models = ["claude", "codex"]
    random.shuffle(models)
    mapping = {"A": models[0], "B": models[1]}
    out = Path(report_dir) / "ab-mapping.json"
    out.write_text(json.dumps(mapping, indent=2))
    print(f"A={mapping['A']}, B={mapping['B']}")

if __name__ == "__main__":
    randomize(sys.argv[1])
```

**Step 2: evaluate.sh を作成**

A/B成果物を eval-prompt.md に埋め込み、Claude CodeとCodexそれぞれに評価させる。

```bash
#!/bin/bash
# Usage: evaluate.sh <YYYY-MM>
YYYYMM=$1
REPORT_DIR="benchmark/reports/${YYYYMM}"

python3 benchmark/scripts/randomize-ab.py "${REPORT_DIR}"

MAPPING=$(cat "${REPORT_DIR}/ab-mapping.json")
A_MODEL=$(echo $MAPPING | python3 -c "import sys,json; print(json.load(sys.stdin)['A'])")
B_MODEL=$(echo $MAPPING | python3 -c "import sys,json; print(json.load(sys.stdin)['B'])")

for TASK in task1 task2 task3; do
  A_OUTPUT=$(cat "${REPORT_DIR}/artifacts/${A_MODEL}/${TASK}/output.md")
  B_OUTPUT=$(cat "${REPORT_DIR}/artifacts/${B_MODEL}/${TASK}/output.md")
  PROMPT=$(cat benchmark/prompts/eval-prompt.md)
  FULL_PROMPT="${PROMPT}

## 成果物A
${A_OUTPUT}

## 成果物B
${B_OUTPUT}"

  # Claude が評価
  claude -p "${FULL_PROMPT}" > "${REPORT_DIR}/artifacts/eval-by-claude-${TASK}.md"
  # Codex が評価
  codex exec --output-last-message "${REPORT_DIR}/artifacts/eval-by-codex-${TASK}.md" \
    "${FULL_PROMPT}"
done
```

**Step 3: generate-report.py を作成**

評価結果 + タスク2自動スコア + ab-mapping.json から `result.md` を生成する。

```python
#!/usr/bin/env python3
"""Generate benchmark result.md from evaluation artifacts."""
import json, sys
from pathlib import Path

def load(path: Path) -> str:
    return path.read_text() if path.exists() else "(未取得)"

def generate(report_dir: str) -> None:
    d = Path(report_dir)
    mapping = json.loads((d / "ab-mapping.json").read_text())
    # A/B -> claude/codex に逆引き
    ab = {v: k for k, v in mapping.items()}

    lines = [f"# Benchmark Result {d.name}\n"]

    # タスク2 自動スコア
    lines.append("## スコアサマリー\n")
    lines.append("| タスク | Claude Code | Codex |")
    lines.append("|--------|------------|-------|")
    claude_score = json.loads((d / "artifacts/claude/task2/score.json").read_text()) if (d / "artifacts/claude/task2/score.json").exists() else {"task2_score": "-"}
    codex_score  = json.loads((d / "artifacts/codex/task2/score.json").read_text())  if (d / "artifacts/codex/task2/score.json").exists()  else {"task2_score": "-"}
    lines.append(f"| タスク2（自動） | {claude_score['task2_score']}/4 | {codex_score['task2_score']}/4 |")
    lines.append("| タスク1・3 | (相互評価参照) | (相互評価参照) |\n")

    # タスクごとの成果物と評価
    for task, label in [("task1","設計"), ("task2","コード生成"), ("task3","レビュー")]:
        lines.append(f"## {label}\n")
        lines.append(f"### Claude Code の成果物\n")
        lines.append(load(d / "artifacts/claude" / task / "output.md"))
        lines.append(f"\n### Codex の成果物\n")
        lines.append(load(d / "artifacts/codex" / task / "output.md"))
        lines.append(f"\n### Claude Code による評価\n")
        lines.append(load(d / f"artifacts/eval-by-claude-{task}.md"))
        lines.append(f"\n### Codex による評価\n")
        lines.append(load(d / f"artifacts/eval-by-codex-{task}.md"))
        lines.append("\n---\n")

    (d / "result.md").write_text("\n".join(lines))
    print(f"Generated: {d / 'result.md'}")

if __name__ == "__main__":
    generate(sys.argv[1])
```

**Step 4: Commit**

```bash
git add benchmark/scripts/randomize-ab.py \
        benchmark/scripts/evaluate.sh \
        benchmark/scripts/generate-report.py
git commit -m "feat: add blind evaluation and report generation scripts"
```

---

## Task 9: 認証確認（手動）

### Claude Code

ブラウザログインで認証する。APIキー不要。

```bash
claude auth login
```

ブラウザが開くので、claude.ai アカウントでログインすること。
ログイン済みであれば `claude -p` がそのまま使える。

### Codex

ブラウザログインで認証する。APIキー不要。

```bash
codex auth login
```

ブラウザが開くので、OpenAI アカウントでログインすること。
ログイン済みであれば `codex exec` がそのまま使える。

---

## 実装順序の依存関係

```
Task 1 (プロンプト) ──┐
Task 2 (採点基準)   ──┴─→ Task 4 (月次Issue GHA)  ←── Task 3 (DevContainer) は独立
                            ↓（Issueを確認したら手動で実行）
                    Task 5 (run-claude.sh)
                    Task 6 (run-codex.sh)
                            ↓
                    Task 7 (eval-task2.sh) ── ⚠️ tflint --init 検証を先に実施
                            ↓
                    Task 8 (evaluate.sh + generate-report.py)
                            ↓
                    Task 9 (環境変数確認)
```
