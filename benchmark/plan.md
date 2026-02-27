# Benchmark タスク定義 Plan

## 前提

- タスクは**毎月固定**（カテゴリ・お題・制約すべて不変）
- テーマ: **IaC（AWS + Terraform）**
- 対象: Claude Code vs Codex

---

## タスク1: 設計

### お題

3層WebアプリケーションをAWSに構築するためのTerraformモジュール構成を設計せよ。

**構成要素:**
- ALB（Application Load Balancer）
- ECS（Fargate）
- RDS（PostgreSQL）

**出力形式:**
- ディレクトリ構成（ファイルツリー形式）
- モジュール分割方針と各モジュールの責務
- 主要な変数・出力値の定義
- Terraformステート管理方針（バックエンド構成含む）

---

### 採点用チェックリスト（10点満点）※Issueには載せない

1. `root / modules / envs`（またはそれに準ずる）のディレクトリ分離がある
2. ALB / ECS / RDS をそれぞれモジュール分割し、責務が明確
3. ネットワーク（VPC / Subnet / RouteTable / NAT）を独立モジュール化
4. セキュリティ（SG / IAM / KMS / Secrets Manager 等）を扱う方針に言及
5. stateバックエンド（S3 + DynamoDB ロック等）に具体的に言及
6. workspace または envディレクトリ戦略が一貫している
7. variables に型・description が付与されている
8. outputs が依存関係に有用（ALB DNS、ECS cluster ARN 等）
9. remote state 参照や依存の扱いが破綻していない
10. マルチ環境（dev / staging / prod）のディレクトリ戦略に言及がある

---

## タスク2: コード生成

### お題

以下の要件を満たすTerraform VPCモジュールを実装せよ。

**要件:**
- パブリックサブネット × 2（マルチAZ）
- プライベートサブネット × 2（マルチAZ）
- Internet Gateway
- NAT Gateway 1個（パブリックサブネットに配置、コスト優先）
- 適切なルートテーブル設定

**制約:**
- Terraform >= 1.0
- AWSプロバイダーバージョンを `versions.tf` で明示すること
- 以下のファイル構成を必須とする:
  - `main.tf` / `variables.tf` / `outputs.tf` / `versions.tf`
- `var.tags` を受け取り、全リソースで `merge` してタグを付与すること
- リソースに適切なタグを付与すること

**自動評価項目（/4点）:**
- `terraform fmt` によるフォーマットチェック
- `terraform init && terraform validate` による構文・型チェック
- `tflint --init && tflint -f compact` によるベストプラクティス検証
- `checkov -d . --framework terraform` によるセキュリティスキャン

---

## タスク3: レビュー

### お題

以下のTerraformコードをレビューせよ。問題点と改善提案を以下のフォーマットで出力すること。

**出力フォーマット（厳守）:**

```
- [CRITICAL|HIGH|MEDIUM|LOW] <対象リソース/箇所> : <問題> -> <改善案>
```

最後に「最優先で直すべきTOP3」を列挙すること。

---

**レビュー対象コード:**

```hcl
provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "main" {
  identifier        = "app-db"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  username          = "admin"
  password          = "password123"
  publicly_accessible  = true
  storage_encrypted    = false
  skip_final_snapshot  = true
}

resource "aws_s3_bucket" "data" {
  bucket = "my-app-data-bucket"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
```

---

**仕込んだ問題点と正解重大度（採点用メモ、Issueには載せない）:**

| # | 対象 | 問題 | 正解重大度 |
|---|------|------|-----------|
| 1 | `aws_security_group.web` | 全ポート（0-65535）全開放 | CRITICAL |
| 2 | `aws_db_instance.main` | パスワードのハードコード | CRITICAL |
| 3 | `aws_db_instance.main` | `publicly_accessible = true`（DBをパブリック公開） | CRITICAL |
| 4 | `aws_db_instance.main` | `storage_encrypted = false`（暗号化無効） | HIGH |
| 5 | `aws_db_instance.main` | `skip_final_snapshot = true`（スナップショットなし） | HIGH |
| 6 | `aws_s3_bucket.data` | パブリックアクセスブロック未設定 | HIGH |
| 7 | 全リソース | タグ付与なし | MEDIUM |

**採点基準（/7点）:**
- 指摘ヒット数: 7問題中何件を指摘できたか（各1点）
- 重大度判定: 各問題で正解重大度と一致しているか（ヒットした問題のみ加点対象）
- TOP3: 上位3件がCRITICAL問題を含んでいるか

---

## レポートスコア構成

毎月の `result.md` に以下を記載する:

| タスク | 客観スコア | 主観スコア |
|--------|-----------|-----------|
| タスク1（設計） | チェックリスト /10 | ★5段階 |
| タスク2（コード生成） | PASS数 /4 | ★5段階 |
| タスク3（レビュー） | 指摘ヒット数 /7 | ★5段階 |
