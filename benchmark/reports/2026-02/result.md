# Benchmark Result 2026-02

## スコアサマリー

| タスク | Claude Code | Codex |
|--------|------------|-------|
| タスク2（自動評価） | 3/4 | 3/4 |
| タスク1・3 | (相互評価参照) | (相互評価参照) |

A=codex, B=claude（評価時のブラインド割り当て）

---

## 設計

### Claude Code の成果物

# Terraform モジュール構成設計：3層 Web アプリケーション (AWS)

---

## 1. ディレクトリ構成

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   ├── staging/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── variables.tf
└── modules/
    ├── networking/          # VPC・サブネット・SG
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── alb/                 # ALB・リスナー・ターゲットグループ
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ecs/                 # Fargate クラスター・サービス・タスク定義
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── rds/                 # RDS PostgreSQL・サブネットグループ
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── iam/                 # ECS タスクロール・実行ロール
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 2. モジュール分割方針

| モジュール | 責務 |
|---|---|
| `networking` | VPC、パブリック/プライベートサブネット、IGW、NAT Gateway、ルートテーブル、セキュリティグループの定義。他モジュールが依存するネットワーク基盤を一元管理する。 |
| `alb` | ALB 本体、HTTPS/HTTP リスナー、ターゲットグループ、ACM 証明書の紐付け。ECS サービスへのトラフィック入口を担う。 |
| `ecs` | Fargate クラスター、タスク定義（コンテナ仕様・環境変数・シークレット参照）、ECS サービス（オートスケーリング含む）を管理。ALB ターゲットグループへ自身を登録する。 |
| `rds` | RDS PostgreSQL インスタンス（Multi-AZ）、サブネットグループ、パラメータグループ、スナップショット設定。ECS からのアクセスのみを許可する SG ルールを持つ。 |
| `iam` | ECS タスク実行ロール（ECR・CloudWatch・Secrets Manager 権限）とタスクロール（アプリ固有 AWS API 権限）を分離して管理。 |

**依存関係の方向性:**

```
networking → alb → ecs → rds
                 ↗
            iam
```

---

## 3. 主要な変数・出力値の定義

### `modules/networking`

```hcl
# variables.tf
variable "env"               { type = string }
variable "vpc_cidr"          { type = string }
variable "az_count"          { type = number; default = 2 }
variable "public_cidr_bits"  { type = number; default = 8 }
variable "private_cidr_bits" { type = number; default = 8 }

# outputs.tf
output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"   { value = aws_subnet.public[*].id }
output "private_subnet_ids"  { value = aws_subnet.private[*].id }
output "alb_sg_id"           { value = aws_security_group.alb.id }
output "ecs_sg_id"           { value = aws_security_group.ecs.id }
output "rds_sg_id"           { value = aws_security_group.rds.id }
```

### `modules/alb`

```hcl
# variables.tf
variable "env"              { type = string }
variable "vpc_id"           { type = string }
variable "subnet_ids"       { type = list(string) }
variable "security_group_id"{ type = string }
variable "certificate_arn"  { type = string }
variable "health_check_path"{ type = string; default = "/health" }

# outputs.tf
output "alb_arn"            { value = aws_lb.main.arn }
output "alb_dns_name"       { value = aws_lb.main.dns_name }
output "target_group_arn"   { value = aws_lb_target_group.app.arn }
output "https_listener_arn" { value = aws_lb_listener.https.arn }
```

### `modules/ecs`

```hcl
# variables.tf
variable "env"                  { type = string }
variable "cluster_name"         { type = string }
variable "vpc_id"               { type = string }
variable "subnet_ids"           { type = list(string) }
variable "security_group_id"    { type = string }
variable "target_group_arn"     { type = string }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn"        { type = string }
variable "container_image"      { type = string }
variable "container_port"       { type = number; default = 8080 }
variable "cpu"                  { type = number; default = 512 }
variable "memory"               { type = number; default = 1024 }
variable "desired_count"        { type = number; default = 2 }
variable "min_capacity"         { type = number; default = 2 }
variable "max_capacity"         { type = number; default = 10 }
variable "db_secret_arn"        { type = string }

# outputs.tf
output "cluster_id"             { value = aws_ecs_cluster.main.id }
output "service_name"           { value = aws_ecs_service.app.name }
output "task_definition_arn"    { value = aws_ecs_task_definition.app.arn }
```

### `modules/rds`

```hcl
# variables.tf
variable "env"                  { type = string }
variable "vpc_id"               { type = string }
variable "subnet_ids"           { type = list(string) }
variable "security_group_id"    { type = string }
variable "db_name"              { type = string }
variable "db_username"          { type = string }
variable "instance_class"       { type = string; default = "db.t4g.medium" }
variable "engine_version"       { type = string; default = "16.2" }
variable "allocated_storage"    { type = number; default = 20 }
variable "multi_az"             { type = bool;   default = true }
variable "deletion_protection"  { type = bool;   default = true }
variable "backup_retention_days"{ type = number; default = 7 }

# outputs.tf
output "db_endpoint"            { value = aws_db_instance.main.endpoint }
output "db_port"                { value = aws_db_instance.main.port }
output "db_name"                { value = aws_db_instance.main.db_name }
output "db_secret_arn"          { value = aws_secretsmanager_secret.db.arn }
```

### `modules/iam`

```hcl
# variables.tf
variable "env"                  { type = string }
variable "db_secret_arn"        { type = string }

# outputs.tf
output "task_execution_role_arn"{ value = aws_iam_role.ecs_task_execution.arn }
output "task_role_arn"          { value = aws_iam_role.ecs_task.arn }
```

---

## 4. Terraform ステート管理方針

### バックエンド構成

S3 をリモートステートストレージ、DynamoDB をロックテーブルとして使用する。

**S3 バケット設計:**

| 設定項目 | 値 |
|---|---|
| バケット名 | `{org}-terraform-state-{account_id}` |
| バージョニング | 有効（誤操作時のロールバック用） |
| サーバーサイド暗号化 | SSE-KMS |
| パブリックアクセス | すべてブロック |
| オブジェクトロック | 無効（バージョニングで代替） |

**DynamoDB テーブル設計:**

| 設定項目 | 値 |
|---|---|
| テーブル名 | `{org}-terraform-lock` |
| パーティションキー | `LockID` (String) |
| 課金モード | PAY_PER_REQUEST |

### `environments/prod/backend.tf` の例

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-terraform-state-123456789012"
    key            = "prod/webapp/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-1:123456789012:key/xxxx"
    dynamodb_table = "myorg-terraform-lock"
  }
}
```

### 環境分離戦略

**ステートファイルのキー設計 (パス分離):**

```
{env}/webapp/terraform.tfstate

例:
  dev/webapp/terraform.tfstate
  staging/webapp/terraform.tfstate
  prod/webapp/terraform.tfstate
```

**環境ごとの `terraform.tfvars` 値の違い:**

| パラメータ | dev | staging | prod |
|---|---|---|---|
| `ecs_desired_count` | 1 | 2 | 4 |
| `rds_instance_class` | db.t4g.micro | db.t4g.medium | db.r8g.large |
| `rds_multi_az` | false | false | true |
| `rds_deletion_protection` | false | true | true |
| `rds_backup_retention_days` | 1 | 7 | 30 |
| `ecs_min_capacity` | 1 | 2 | 4 |
| `ecs_max_capacity` | 2 | 4 | 20 |

**IAM アクセス制御:**

- dev/staging: 開発者ロールに `terraform apply` 権限を付与
- prod: CI/CD パイプライン専用ロールのみに `terraform apply` を限定し、手動適用を禁止

**ワークスペース vs ディレクトリ分離:**

本設計では `terraform workspace` は採用せず、**`environments/` ディレクトリによる分離**を選択する。理由は以下の通り。

- ステートファイルの誤操作リスクを低減できる
- 環境ごとに `backend.tf` の KMS キーや IAM ロールを明示的に切り替えられる
- CI/CD パイプラインでの `cd environments/prod && terraform apply` のように意図が明確になる


### Codex の成果物

**1. ディレクトリ構成（例）**
```text
terraform/
├── modules/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── alb/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecs_fargate/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds_postgres/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── security/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── backend.hcl
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── stg/
│   │   ├── backend.hcl
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── backend.hcl
│       ├── main.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── terraform.tfvars
└── README.md
```

**2. モジュール分割方針**
- `network`: VPC、Public/Private Subnet、RouteTable、Internet/NAT Gateway。
- `security`: SGを集約管理（ALB用、ECS用、RDS用）し、許可方向を明示。
- `alb`: ALB、Listener、Target Group。ECSサービスの入口を提供。
- `ecs_fargate`: ECS Cluster、Task Definition、Service、CloudWatch Logs、AutoScaling。
- `rds_postgres`: RDS PostgreSQL、Subnet Group、Parameter Group、Option Group、バックアップ設定。

**3. 主要な変数・出力値定義（代表例）**

`modules/network/variables.tf`
```hcl
variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_app_subnet_cidrs" { type = list(string) }
variable "private_db_subnet_cidrs" { type = list(string) }
```

`modules/network/outputs.tf`
```hcl
output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_app_subnet_ids" { value = aws_subnet.private_app[*].id }
output "private_db_subnet_ids" { value = aws_subnet.private_db[*].id }
```

`modules/alb/variables.tf`
```hcl
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "target_port" { type = number }
variable "health_check_path" { type = string }
variable "certificate_arn" { type = string, default = null }
```

`modules/alb/outputs.tf`
```hcl
output "alb_arn" { value = aws_lb.this.arn }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "target_group_arn" { value = aws_lb_target_group.app.arn }
```

`modules/ecs_fargate/variables.tf`
```hcl
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "ecs_sg_id" { type = string }
variable "target_group_arn" { type = string }
variable "container_image" { type = string }
variable "container_port" { type = number }
variable "desired_count" { type = number }
variable "cpu" { type = number }
variable "memory" { type = number }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
```

`modules/ecs_fargate/outputs.tf`
```hcl
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "service_name" { value = aws_ecs_service.this.name }
output "task_definition_arn" { value = aws_ecs_task_definition.this.arn }
```

`modules/rds_postgres/variables.tf`
```hcl
variable "name" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "rds_sg_id" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "db_name" { type = string }
variable "username" { type = string }
variable "password" { type = string, sensitive = true }
variable "multi_az" { type = bool }
variable "backup_retention_period" { type = number }
```

`modules/rds_postgres/outputs.tf`
```hcl
output "db_instance_id" { value = aws_db_instance.this.id }
output "db_endpoint" { value = aws_db_instance.this.address }
output "db_port" { value = aws_db_instance.this.port }
```

`modules/security/variables.tf`
```hcl
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "app_port" { type = number }
variable "db_port" { type = number }
```

`modules/security/outputs.tf`
```hcl
output "alb_sg_id" { value = aws_security_group.alb.id }
output "ecs_sg_id" { value = aws_security_group.ecs.id }
output "rds_sg_id" { value = aws_security_group.rds.id }
```

**4. Terraformステート管理方針**

- バックエンドは `S3 + DynamoDB` を使用。
- S3はバージョニング有効化、SSE有効化、Public Access Block有効化。
- DynamoDBは `LockID` パーティションキーで状態ロック管理。
- 環境分離は `environments/dev|stg|prod` のディレクトリ分離を採用（Workspace依存を避ける）。
- Stateキーは環境ごとに分離（例: `project/dev/terraform.tfstate`）。

`environments/dev/main.tf` の backend 宣言（partial）
```hcl
terraform {
  backend "s3" {}
}
```

`environments/dev/backend.hcl` 例
```hcl
bucket         = "my-tfstate-bucket"
key            = "three-tier-web/dev/terraform.tfstate"
region         = "ap-northeast-1"
dynamodb_table = "my-tfstate-locks"
encrypt        = true
```

初期化例
```bash
cd environments/dev
terraform init -backend-config=backend.hcl
```

この構成にすると、モジュール再利用性と環境ごとの独立性を両立しやすいです。

### Claude Code による評価

## 成果物A 評価

- **正確性: ★4** / VPC・ALB・ECS Fargate・RDS の主要コンポーネントを網羅しており構成は正確。ただし IAM ロール管理が外部依存（変数入力）のみでモジュールとして提供されていない点が欠ける。
- **安全性: ★3** / `password` 変数に `sensitive = true` を付けている点は評価できるが、Secrets Manager を使わず変数でパスワードを渡す設計は本番要件として不十分。S3 の SSE が KMS 指定なく暗号化方式が曖昧。RDS の `deletion_protection` も未定義。
- **可読性: ★3** / 構成はシンプルで全体像を把握しやすいが、変数定義に `description` フィールドがなく、各モジュールの責務や設計意図を読み解くにはコードを追う必要がある。
- **ベストプラクティス: ★4** / `backend.hcl` を分離した Partial Backend 構成は CI/CD との親和性が高く評価できる。Workspace ではなくディレクトリ分離を選択した点も適切。一方で `validation` ブロックや variable `description` の省略、IAM モジュールの欠如がマイナス。

**総合コメント:** 基本構成として機能するシンプルな設計だが、セキュリティ面（Secrets Manager 未使用・KMS 未指定・削除保護なし）に実運用上の懸念が残る。設計意図のドキュメントも薄い。

---

## 成果物B 評価

- **正確性: ★5** / VPC・ALB・ECS・RDS に加えて専用の IAM モジュールを持ち、Secrets Manager 連携（`db_secret_arn`）・オートスケーリングの min/max・HTTPS リスナー ARN 出力など実運用で必要な要素を網羅している。
- **安全性: ★5** / DB 認証情報を Secrets Manager で管理、S3 ステートは SSE-KMS 指定、RDS に `deletion_protection`・Multi-AZ デフォルト設定あり。本番環境への手動 apply 禁止（CI/CD 専用ロール）まで言及しており、多層的なセキュリティ設計になっている。
- **可読性: ★4** / モジュール責務の一覧表・依存関係図・環境別パラメータ比較表・Workspace vs ディレクトリ分離の理由付けが揃っており文書として読みやすい。ただし変数定義でセミコロン区切り（`{ type = string; default = 2 }`）を使っており、HCL2 では動作するものの非慣用的な記法でツールチェーン（`terraform fmt`・`tflint`）との相性が悪い。
- **ベストプラクティス: ★4** / IAM を独立モジュール化・Secrets Manager 統合・PAY_PER_REQUEST DynamoDB と、多くのベストプラクティスを実装。セミコロン記法が `terraform fmt` の標準スタイルと異なる点と、SG をネットワークモジュールに内包する設計（他モジュールとの疎結合を下げうる）は軽微な減点要因。

**総合コメント:** セキュリティ・完全性・ドキュメントの三点でバランスが取れた設計。本番環境を視野に入れた具体的な運用方針（環境別パラメータ・IAM アクセス制御）まで踏み込んでいる点が実践的。

---

## 最終判定

**成果物B が総合的に優れている。**

決定的な差はセキュリティ設計にある。成果物A が DB パスワードを Terraform 変数として扱うのに対し、成果物B は Secrets Manager を介してパスワードをステートファイルに載せない設計を採用しており、これは本番運用で必須の要件に相当する。さらに SSE-KMS・削除保護・CI/CD 限定 apply と多層防御が組み込まれている点も実運用での信頼性が高い。

一方、成果物A の `backend.hcl` 分離アプローチは CI/CD 上の柔軟性という点でBの `backend.tf` 方式より優れており、この点は A に軍配が上がる。全体として B は設計の厚みと安全性で A を上回っており、より本番グレードの設計と評価する。


### Codex による評価

### 成果物A 評価
- 正確性: ★4 / 3層構成に必要な主要モジュール（Network/ALB/ECS/RDS/SG分離）と入出力が揃っており、実装方針として成立しています。  
- 安全性: ★3 / `password` を変数で受ける設計は可能ですが、Secret Manager連携やRDSの`deletion_protection`等の強制方針が明示されておらず、運用次第でリスクが残ります。  
- 可読性: ★4 / ディレクトリ分離と責務分割が明快で追いやすいです。説明も簡潔ですが、環境ごとの差分ポリシーはもう少し具体化できる余地があります。  
- ベストプラクティス: ★4 / `environments/`分離、S3+DynamoDBロック、backend partial configは良い実践です。加えてバリデーション・`required_providers`・`required_version`の明示があるとさらに良いです。  
- 総合コメント: 構成のバランスが良く、実装に落とし込みやすい設計です。セキュリティ強化項目（秘密情報管理、破壊防止設定）を明文化すると完成度が上がります。

### 成果物B 評価
- 正確性: ★4 / IAM分離やSecrets Manager連携まで含めた設計は実運用向きです。一方で依存関係図（`networking → alb → ecs → rds`）は実際の依存をやや誤解しやすく、設計上の注意点です。  
- 安全性: ★4 / SSE-KMS、prod適用権限制限、RDS削除保護など具体策が明示されており強いです。実コードで最小権限IAMポリシーを徹底できるかが最終的な鍵です。  
- 可読性: ★4 / 表形式と具体例が多く、設計意図は理解しやすいです。情報量が多いため、実装者向けには必須項目と任意項目の分離があるとさらに読みやすくなります。  
- ベストプラクティス: ★4 / 環境分離、ロック、ロール分離など実務的に良いです。`backend.tf`に環境固有値を直書きする運用は再利用性・秘匿性の観点でA方式（partial config）に劣る面があります。  
- 総合コメント: セキュリティ運用まで踏み込んだ、実務寄りで強い設計です。依存関係の整理とbackend値の扱いを改善するとさらに堅くなります。

### 最終判定
**Bが総合的にやや優位**です。理由は、IAMロール分離・Secrets Manager・prod適用制御など、実運用で重要な安全性要件まで具体化しているためです。  
ただし、**Terraform実装の素直さと再利用性（backend partial config、責務分離）ではAにも明確な強み**があり、実装フェーズではAの構造にBのセキュリティ方針を取り込むのが最適です。

---

## コード生成

### Claude Code の成果物

```hcl:main.tf
locals {
  tags = var.tags
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags, {
    Name = "${var.name}-private-${count.index + 1}"
    Tier = "private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.this]
}

# NAT Gateway (single, cost-optimized)
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = "${var.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

```hcl:variables.tf
variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of two availability zones to use"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones must be specified."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs must be specified."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDRs must be specified."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

```hcl:outputs.tf
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}
```

```hcl:versions.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

---

## 利用例

```hcl
module "vpc" {
  source = "./modules/vpc"

  name               = "myapp-prod"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  tags = {
    Environment = "production"
    Project     = "myapp"
    ManagedBy   = "terraform"
  }
}
```

## 設計上のポイント

| 項目 | 判断 |
|------|------|
| NAT Gateway | 1個のみ（コスト優先。HA優先なら各AZに1個ずつ配置） |
| プライベートRT | 単一（両プライベートサブネットが同一NATを経由） |
| `depends_on` | EIP・NAT GWはIGWアタッチ後に作成されるよう明示 |
| `var.tags` | 全リソースで `merge()` し、リソース固有の `Name`/`Tier` タグを上書き可能な形で付与 |
| バリデーション | AZ・サブネットCIDRは必ず2要素であることを `validation` で保証 |


### Codex の成果物

```hcl:main.tf
locals {
  public_subnet_map = {
    for i, az in var.azs : az => {
      cidr = var.public_subnet_cidrs[i]
      az   = az
      idx  = i + 1
    }
  }

  private_subnet_map = {
    for i, az in var.azs : az => {
      cidr = var.private_subnet_cidrs[i]
      az   = az
      idx  = i + 1
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.value.idx}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnet_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.value.idx}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.azs[0]].id
  depends_on    = [aws_internet_gateway.this]

  tags = merge(var.tags, {
    Name = "${var.name}-natgw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
```

```hcl:variables.tf
variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Exactly 2 availability zones."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "azs must contain exactly 2 AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "Exactly 2 CIDR blocks for public subnets."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "Exactly 2 CIDR blocks for private subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly 2 CIDRs."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
```

```hcl:outputs.tf
output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID."
  value       = aws_nat_gateway.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = [for az in var.azs : aws_subnet.private[az].id]
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID."
  value       = aws_route_table.private.id
}
```

```hcl:versions.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### Claude Code による評価

### 成果物A 評価

- **正確性: ★5** / `for_each` を AZ キーのマップで駆動しており、サブネットと AZ の対応が厳密に保証されている。DNS 設定を変数化するなど要件を過不足なく満たしている。
- **安全性: ★4** / ハードコード値がなく、外部からの制御が可能。VPC Flow Logs は未設定だがスコープ外として許容範囲。
- **可読性: ★4** / `locals` の二重マップは初見でやや理解に時間がかかるが、リソースブロック自体は整然としており変数名・タグ設計も一貫している。
- **ベストプラクティス: ★5** / `for_each` の採用（count よりリソースの安定性が高い）、`aws_route` を独立リソースとして分離、不必要な中間 local なし、全変数にバリデーション付与と、HCL のベストプラクティスを高水準で実践している。
- **総合コメント:** モジュールとしての堅牢性・拡張性が高く、本番環境向けの設計として完成度が高い。`enable_dns_*` が可変なのも実用的。

---

### 成果物B 評価

- **正確性: ★4** / 基本要件は満たしているが、`count = 2` のハードコードは変数 `availability_zones` の length と乖離する恐れがある。また EIP に `depends_on = [aws_internet_gateway.this]` を付けているが EIP は IGW に依存しないため技術的に不正確。
- **安全性: ★4** / デフォルト CIDR (`10.0.0.0/24` 等) がモジュール変数に設定されており、複数環境で使い回した際に IP 重複を引き起こすリスクがある。`enable_dns_*` がハードコードで隠蔽されているのも柔軟性を損なう。
- **可読性: ★4** / インラインコメントやデフォルト値の提供で初学者には親切。ただし `locals { tags = var.tags }` は冗長な間接参照で可読性を微妙に下げている。
- **ベストプラクティス: ★3** / `count = 2` のマジックナンバーは `length(var.availability_zones)` で動的にすべき。ルートをルートテーブルインラインで定義するとルート単体の更新が困難になる。不要な中間 local と誤った依存関係が設計の瑕疵。
- **総合コメント:** デフォルト値やコメントで使いやすさを高めているが、柔軟性・正確性の面で妥協点が多く、プロダクション用モジュールとしてはリファクタリングが必要。

---

### 最終判定

**成果物A が総合的に優れている。**

最大の差異は `for_each` vs `count` の選択にある。A の `for_each` はサブネットをインデックスではなく AZ 名で識別するため、リソースの追加・削除時に既存リソースを破壊しない。B の `count = 2` はハードコードかつインデックスベースのため、順序変更や将来の AZ 追加で意図しない destroy/recreate が発生しうる。加えて A は DNS 設定の可変化、独立した `aws_route` リソース、冗長なコードなしの設計で、**再利用性・安全性・ベストプラクティス準拠のすべてにおいて B を上回っている。**


### Codex による評価

### 成果物A 評価
- 正確性: ★4 / VPC・IGW・2つのPublic/Private Subnet・NAT・RT関連が一通り整っており、2AZ前提の構成として技術的に成立しています。`for_each` と入力バリデーションでAZとCIDRの対応も比較的堅牢です。  
- 安全性: ★4 / Public/Private分離とPrivate側のデフォルトルートをNATに向ける基本は押さえています。なお、NATが単一AZである点は可用性リスク（セキュリティというより運用リスク）が残ります。  
- 可読性: ★4 / 構成は素直で、`locals` によるマップ化で意図が読み取りやすいです。コメントが少ないため、設計意図（単一NAT採用理由など）はコードだけだと伝わりにくいです。  
- ベストプラクティス: ★5 / `count` より変更耐性の高い `for_each` を使い、変数・出力・providers定義も整理されています。命名やタグ付けも一貫しており、Terraformモジュールとしての完成度が高いです。  
- 総合コメント: 実装の安定性とTerraformらしい書き方のバランスが良く、運用時の差分管理に強い構成です。

### 成果物B 評価
- 正確性: ★4 / 同じく2AZ前提のVPC基盤としては動作可能で、利用例や設計方針の明示もあります。`enable_dns_*` が固定値で変数化されていないため、要件変更への追従性はAより低いです。  
- 安全性: ★4 / ネットワーク分離とNAT経由の外向き通信という基本は満たしています。A同様に単一NATのため、AZ障害時の通信継続性には課題が残ります。  
- 可読性: ★5 / セクションコメント、利用例、設計判断テーブルがあり、読み手が意図を把握しやすいです。初見の利用者向けドキュメント性は高いです。  
- ベストプラクティス: ★3 / `count = 2` 固定と index 依存は、将来の変更時にリソース再作成リスクがあり `for_each` より不利です。不要気味な `depends_on` や固定値設定もモジュール設計としてはやや硬直的です。  
- 総合コメント: 説明は丁寧で分かりやすい一方、Terraformとしての拡張性・変更耐性はAに劣ります。

### 最終判定
総合的には **Aの方が優れています**。理由は、実装の正確性が同程度でも、`for_each` ベースの設計・変数化の粒度・将来変更に対する安定性といったTerraform実務で重要な観点でAが一段上だからです。

---

## レビュー

### Claude Code の成果物

Terraformコードのレビュー結果です。

---

## レビュー結果

- [CRITICAL] `aws_db_instance.main` / `password` : パスワードがソースコードにハードコードされており、バージョン管理に平文で残存する -> `var` または AWS Secrets Manager / SSM Parameter Store を使用し、`sensitive = true` を付与する

- [CRITICAL] `aws_security_group.web` / `ingress` : 全ポート(0-65535)を全IPアドレス(0.0.0.0/0)に開放しており、無制限のインバウンドアクセスを許可している -> 必要なポート(80, 443等)のみに限定し、信頼できるCIDRのみ許可する

- [CRITICAL] `aws_db_instance.main` / `publicly_accessible = true` : RDSインスタンスがインターネットから直接アクセス可能な状態になっている -> `false` に設定し、プライベートサブネット内に配置する

- [HIGH] `aws_db_instance.main` / `storage_encrypted = false` : 保存データが暗号化されていないため、ストレージへの不正アクセス時にデータが漏洩する -> `storage_encrypted = true` に変更し、`kms_key_id` でカスタムKMSキーを指定する

- [HIGH] `aws_db_instance.main` / `skip_final_snapshot = true` : インスタンス削除時にスナップショットが作成されず、データが完全に失われる -> `skip_final_snapshot = false` かつ `final_snapshot_identifier` を指定する

- [HIGH] `aws_db_instance.main` / `backup_retention_period` 未設定 : デフォルト値0となりバックアップが無効化される -> `backup_retention_period = 7`(最低7日)以上を明示的に設定する

- [HIGH] `aws_s3_bucket.data` / パブリックアクセスブロック未設定 : バケットポリシーの設定ミス次第でデータが公開される -> `aws_s3_bucket_public_access_block` リソースを追加し4項目すべて `true` に設定する

- [MEDIUM] `aws_db_instance.main` / `deletion_protection` 未設定 : 誤操作でDBが削除されるリスクがある -> `deletion_protection = true` を追加する

- [MEDIUM] `aws_s3_bucket.data` / サーバーサイド暗号化未設定 : S3上のデータが平文で保存される -> `aws_s3_bucket_server_side_encryption_configuration` を追加し AES-256 または KMS を設定する

- [MEDIUM] `aws_s3_bucket.data` / バージョニング未設定 : 誤削除・上書き時のデータ復旧が不可能 -> `aws_s3_bucket_versioning` リソースを追加し `enabled` に設定する

- [MEDIUM] `aws_db_instance.main` / `multi_az` 未設定 : 単一AZ構成のためAZ障害時にダウンタイムが発生する -> 本番環境では `multi_az = true` を設定する

- [MEDIUM] `provider "aws"` / `required_providers` バージョン制約なし : プロバイダーバージョンが固定されておらず、予期しない破壊的変更が適用される恐れがある -> `terraform` ブロックで `required_providers` にバージョン制約を明記する

- [LOW] `aws_security_group.web` / `description` 未設定 : セキュリティグループの用途が不明瞭になる -> `description` フィールドで用途を説明する文字列を設定する

- [LOW] `aws_s3_bucket.data` / アクセスログ未設定 : バケットへのアクセス監査が不可能 -> `aws_s3_bucket_logging` を設定し別バケットにログを出力する

---

## 最優先で直すべきTOP3

1. **[CRITICAL] RDSパスワードのハードコード** — 認証情報がリポジトリに残存することはセキュリティ上最大のリスク。即座に `var` + Secrets Manager へ移行する。

2. **[CRITICAL] RDSの `publicly_accessible = true`** — データベースがインターネットに直接露出しており、攻撃対象となる。プライベートサブネット配置 + `false` に変更する。

3. **[CRITICAL] セキュリティグループの全ポート開放** — 攻撃面が最大化されている。必要なポートのみに最小権限原則で制限する。


### Codex の成果物

- [CRITICAL] `aws_security_group.web.ingress` : `0.0.0.0/0` に対して `tcp 0-65535` を全面開放しており、全ポートがインターネット公開される -> 必要最小限のポート（例: 80/443）のみに絞り、送信元CIDRも限定する
- [CRITICAL] `aws_db_instance.main.password` : DBパスワードを平文でコードに直書きしており漏洩リスクが高い -> `variable` + `sensitive = true` を使い、AWS Secrets Manager/SSM Parameter Store から参照する
- [HIGH] `aws_db_instance.main.publicly_accessible` : RDSがパブリックアクセス可能で外部攻撃面が拡大している -> `publicly_accessible = false` にし、Private Subnet + 厳格なSecurity Group経由のみにする
- [HIGH] `aws_db_instance.main.storage_encrypted` : RDS暗号化が無効で保存データ保護要件を満たせない -> `storage_encrypted = true`（必要に応じてKMSキー指定）にする
- [HIGH] `aws_db_instance.main.skip_final_snapshot` : 削除時に最終スナップショットを取得せず復旧不能リスクがある -> `skip_final_snapshot = false` とし `final_snapshot_identifier` を設定する
- [HIGH] `aws_s3_bucket.data` : バケット暗号化・公開ブロック・バージョニングが未設定で、漏洩/改ざん/復旧性のリスクがある -> `server_side_encryption_configuration`、`aws_s3_bucket_public_access_block`、`versioning` を追加する
- [MEDIUM] `aws_db_instance.main` : バックアップ保持期間や削除保護が未設定で運用事故耐性が低い -> `backup_retention_period` と `deletion_protection` を有効化する
- [MEDIUM] `provider "aws"` : Providerバージョン固定がなく再現性が低い -> `required_providers` でAWS Providerのバージョン制約を明示する
- [LOW] `aws_s3_bucket.data.bucket` : 固定名はグローバル一意衝突や環境間競合を起こしやすい -> 接頭辞/サフィックス（環境名・アカウントID等）を付与して一意化する

最優先で直すべきTOP3
1. `aws_security_group.web.ingress` の全ポート全開放を即時停止（最小権限化）
2. `aws_db_instance.main.password` の平文管理を廃止（Secrets Manager/SSM化）
3. `aws_db_instance.main.publicly_accessible = true` を無効化してRDSをプライベート配置

### Claude Code による評価

### 成果物A 評価

- **正確性: ★4** / 主要な問題（SG全開放・DBパスワード平文・RDS公開・暗号化なし等）を網羅しているが、`backup_retention_period` のデフォルト値が0であるという重要な技術的詳細や、multi_az未設定、SGの`description`欠落、S3アクセスログ未設定が見落とされている。
- **安全性: ★4** / CRITICALな3点（SG・パスワード・RDS公開）を正しく最優先に挙げており、実用的。ただし可用性（multi_az）や監査ログ（S3ログ）の観点が欠けている。
- **可読性: ★3** / severity付きの箇条書きは見やすいが、S3の複数問題を1行にまとめている箇所があり、個別の追跡が難しい。MDのヘッダー構造もなく、長文になると読み疲れる。
- **ベストプラクティス: ★3** / `variable + sensitive = true`、Secrets Manager、プライベートサブネット等の方向性は正しいが、Terraformリソース名（`aws_s3_bucket_public_access_block`等）の明示が少なく、具体性に欠ける部分がある。
- **総合コメント:** 重要な問題を正確に捉えており実用性は高いが、網羅性・具体性・構造化において改善余地がある。

---

### 成果物B 評価

- **正確性: ★5** / AのすべてをカバーしたうえでA未検出の問題（multi_az・SGのdescription欠落・S3アクセスログ未設定）も発見し、`backup_retention_period`のデフォルト値が0という重要な技術的事実も正確に指摘している。
- **安全性: ★5** / CRITICAL 3点の優先順位付けが適切で、HIGH/MEDIUM/LOWの分類も論理的。可用性リスク（multi_az）や監査ログ（S3ログ）まで含め、多層的なリスク評価ができている。
- **可読性: ★4** / 各findingが「リソース / 属性 / 問題 / 対策」の統一フォーマットで記述されており、追跡しやすい。見出し構造も明確で走査性が高い。全体的にやや冗長な面はある。
- **ベストプラクティス: ★5** / `aws_s3_bucket_public_access_block`・`aws_s3_bucket_versioning`・`aws_s3_bucket_logging`等の正確なTerraformリソース名を使用し、`backup_retention_period = 7`（最低7日）のような具体的な推奨値も示している。multi_azを「本番環境では」と文脈付きで推奨しており、設計判断の質が高い。
- **総合コメント:** 網羅性・技術的精度・構造の三点が高水準で揃っており、実際の改修作業に即つなげられるレビュー品質。

---

### 最終判定

**成果物B が総合的に優れている。**

AとBは共通の重要問題を正確に捉えているが、BはAの指摘を全て包含したうえで追加の問題（multi_az、SGのdescription、S3アクセスログ、backup_retention_periodのデフォルト0という技術的落とし穴）を検出している。加えて、Terraformの正確なリソース名と具体的な推奨値を提示しており、即座に修正コードへ落とし込める実用性がAを上回る。構造化の点でも各findingが統一フォーマットで記述され、レビュー結果としての完成度が高い。


### Codex による評価

### 成果物A 評価
- 正確性: ★4 / 主要な指摘（SG全開放、RDS公開、平文PW、暗号化不足など）は技術的に妥当です。細部では実装方法の具体性がやや粗く、最新Provider流儀（S3関連の分離リソース等）への言及は弱めです。  
- 安全性: ★5 / 重大な攻撃面と情報漏えいリスクを優先度高く押さえており、是正方針も最小権限・秘匿化・非公開化に沿っています。  
- 可読性: ★4 / 重要度別に整理され、TOP3も明確で実務で動きやすい構成です。反面、レビュー観点の網羅性や背景説明は最小限です。  
- ベストプラクティス: ★3 / `required_providers` など基本は押さえていますが、Terraformの実装ベストプラクティス（S3周辺のリソース分離や運用前提別の設計指針）まで踏み込めていません。  
- 総合コメント: 重要リスクの特定と優先順位付けが的確で、短時間で是正着手するレビューとして強いです。

### 成果物B 評価
- 正確性: ★3 / 多くは妥当ですが、「`backup_retention_period`未設定=デフォルト0」の断定など、事実・前提依存の記述が混在しています。`multi_az` も環境要件次第で一律必須とは言いにくいです。  
- 安全性: ★5 / セキュリティ上の重大論点を広くカバーしており、改善策も具体的です。  
- 可読性: ★5 / セクション構成、粒度、表記の統一が良く、レビュー結果として非常に読みやすいです。  
- ベストプラクティス: ★4 / `aws_s3_bucket_public_access_block` や `aws_s3_bucket_server_side_encryption_configuration` など、Terraform実装に寄せた具体提案は良いです。  
- 総合コメント: 網羅性と実装具体性は高い一方、前提依存の断定が混じるため、適用時に環境文脈での精査が必要です。

### 最終判定
**Aの方が総合的に優れている**と判断します。  
理由は、Bは網羅的で読みやすい反面、いくつか前提依存の断定（正確性のブレ）があり、レビュー品質の芯となる信頼性でAがわずかに上回るためです。

---
