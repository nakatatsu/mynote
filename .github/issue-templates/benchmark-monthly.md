## 概要

YYYY-MM 月次ベンチマーク実施リマインダー。
DevContainer内で以下の手順に従い Claude Code / Codex それぞれにタスクを実行させ、成果物を保存・評価・レポート化すること。

---

## タスク定義

### タスク1: 設計

3層WebアプリケーションをAWSに構築するためのTerraformモジュール構成を設計せよ。

**構成要素:** ALB（Application Load Balancer）/ ECS（Fargate）/ RDS（PostgreSQL）

**出力形式:**
- ディレクトリ構成（ファイルツリー形式）
- モジュール分割方針と各モジュールの責務
- 主要な変数・出力値の定義
- Terraformステート管理方針（バックエンド構成含む）

---

### タスク2: コード生成

以下の要件を満たすTerraform VPCモジュールを実装せよ。

**要件:**
- パブリックサブネット × 2（マルチAZ）
- プライベートサブネット × 2（マルチAZ）
- Internet Gateway
- NAT Gateway 1個（パブリックサブネットに配置、コスト優先）
- 適切なルートテーブル設定

**制約:** Terraform >= 1.0 / `main.tf` `variables.tf` `outputs.tf` `versions.tf` の4ファイル構成 / `var.tags` を全リソースで merge してタグ付与

---

### タスク3: レビュー

`benchmark/prompts/task3-review.md` に記載のTerraformコードをレビューせよ。
`[CRITICAL|HIGH|MEDIUM|LOW] <対象> : <問題> -> <改善案>` 形式で出力し、最優先TOP3を列挙すること。

---

## 実施手順

```bash
# 1. Claude Code 実行
bash benchmark/scripts/run-claude.sh

# 2. Codex 実行
bash benchmark/scripts/run-codex.sh

# 3. タスク2 自動評価
bash benchmark/scripts/eval-task2.sh claude YYYY-MM
bash benchmark/scripts/eval-task2.sh codex YYYY-MM

# 4. 相互ブラインド評価 & レポート生成
bash benchmark/scripts/evaluate.sh YYYY-MM
python3 benchmark/scripts/generate-report.py benchmark/reports/YYYY-MM
```

---

## チェックリスト

- [ ] Claude Code タスク1完了
- [ ] Claude Code タスク2完了
- [ ] Claude Code タスク3完了
- [ ] Codex タスク1完了
- [ ] Codex タスク2完了
- [ ] Codex タスク3完了
- [ ] タスク2 自動評価完了（Claude Code）
- [ ] タスク2 自動評価完了（Codex）
- [ ] 相互ブラインド評価完了
- [ ] result.md コミット・プッシュ完了
