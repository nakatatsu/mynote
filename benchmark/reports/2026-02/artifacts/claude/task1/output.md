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
