# Benchmark Result 2026-05

## スコアサマリー

| タスク | Claude Code | Codex |
|--------|------------|-------|
| タスク2（自動評価） | 3/4 | 3/4 |
| タスク1・3 | (相互評価参照) | (相互評価参照) |

A=claude, B=codex（評価時のブラインド割り当て）

---

## 設計

### Claude Code の成果物

# Terraform モジュール設計: 3層Webアプリケーション（AWS）

## 1. ディレクトリ構成

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── stg/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── backend.tf
├── modules/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── alb/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecs/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── rds/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── shared/
    └── backend-setup/
        ├── main.tf
        └── variables.tf
```

## 2. モジュール分割方針

| モジュール | 責務 |
|-----------|------|
| **network** | VPC、サブネット（public/private/isolated）、IGW、NAT Gateway、ルートテーブル、基盤となるセキュリティグループ |
| **alb** | ALB本体、リスナー（HTTP/HTTPS）、ターゲットグループ、ALB用セキュリティグループ、ACM証明書の参照 |
| **ecs** | ECSクラスター、タスク定義、Fargateサービス、IAMロール（タスク実行/タスク）、ECS用セキュリティグループ、CloudWatch Logsロググループ、Auto Scaling設定 |
| **rds** | RDSインスタンス（PostgreSQL）、DBサブネットグループ、パラメータグループ、RDS用セキュリティグループ、Secrets Manager（DB認証情報） |

**分割の原則**: ライフサイクルとチーム責務の境界で分割する。networkは全レイヤの基盤、alb/ecs/rdsは各層に対応し、独立してplan/applyできる粒度にする。

## 3. 主要な変数・出力値の定義

### modules/network

```hcl
# variables.tf
variable "project" {
  type        = string
  description = "プロジェクト名（リソースの命名に使用）"
}

variable "env" {
  type        = string
  description = "環境名（dev/stg/prod）"
}

variable "vpc_cidr" {
  type        = string
  description = "VPCのCIDRブロック"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "使用するAZの数"
  default     = 2
}
```

```hcl
# outputs.tf
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "ALB配置用パブリックサブネット"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "ECS Fargate配置用プライベートサブネット"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "RDS配置用アイソレーテッドサブネット"
  value       = aws_subnet.isolated[*].id
}
```

### modules/alb

```hcl
# variables.tf
variable "project" { type = string }
variable "env"     { type = string }

variable "vpc_id" {
  type        = string
  description = "networkモジュールから受け取るVPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "ALBを配置するパブリックサブネット"
}

variable "certificate_arn" {
  type        = string
  description = "ACM証明書のARN"
  default     = ""
}

variable "health_check_path" {
  type    = string
  default = "/health"
}
```

```hcl
# outputs.tf
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ECSサービスに渡すターゲットグループARN"
  value       = aws_lb_target_group.main.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}
```

### modules/ecs

```hcl
# variables.tf
variable "project" { type = string }
variable "env"     { type = string }

variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "target_group_arn"   { type = string }
variable "alb_security_group_id" { type = string }

variable "container_image" {
  type        = string
  description = "デプロイするコンテナイメージURI"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "db_secret_arn" {
  type        = string
  description = "RDSモジュールから受け取るDB接続情報のSecret ARN"
}
```

```hcl
# outputs.tf
output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.main.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}
```

### modules/rds

```hcl
# variables.tf
variable "project" { type = string }
variable "env"     { type = string }

variable "vpc_id"              { type = string }
variable "isolated_subnet_ids" { type = list(string) }
variable "ecs_security_group_id" {
  type        = string
  description = "ECSからの接続を許可するSG ID"
}

variable "engine_version" {
  type    = string
  default = "16.4"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = true
}
```

```hcl
# outputs.tf
output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_secret_arn" {
  description = "Secrets ManagerのARN（ECSタスク定義で参照）"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}
```

### environments/dev/main.tf（モジュール呼び出し例）

```hcl
module "network" {
  source   = "../../modules/network"
  project  = var.project
  env      = var.env
  vpc_cidr = "10.0.0.0/16"
}

module "alb" {
  source            = "../../modules/alb"
  project           = var.project
  env               = var.env
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
}

module "rds" {
  source                = "../../modules/rds"
  project               = var.project
  env                   = var.env
  vpc_id                = module.network.vpc_id
  isolated_subnet_ids   = module.network.isolated_subnet_ids
  ecs_security_group_id = module.ecs.ecs_security_group_id
}

module "ecs" {
  source                 = "../../modules/ecs"
  project                = var.project
  env                    = var.env
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  target_group_arn       = module.alb.target_group_arn
  alb_security_group_id  = module.alb.alb_security_group_id
  container_image        = var.container_image
  db_secret_arn          = module.rds.db_secret_arn
}
```

## 4. Terraformステート管理方針

### バックエンド構成

```hcl
# environments/dev/backend.tf
terraform {
  backend "s3" {
    bucket         = "myproject-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "myproject-terraform-lock"
  }
}
```

### バックエンドリソースの初期構築（shared/backend-setup/main.tf）

```hcl
resource "aws_s3_bucket" "tfstate" {
  bucket = "myproject-terraform-state"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = "myproject-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### 環境分離戦略

| 方針 | 内容 |
|------|------|
| **ステートファイル分離** | 環境ごとにS3キーを分離（`dev/terraform.tfstate`, `stg/terraform.tfstate`, `prod/terraform.tfstate`） |
| **S3バケット** | 全環境で1バケットを共有し、キープレフィックスで分離。AWSアカウントを分ける場合はバケットも分離する |
| **ロックテーブル** | DynamoDBテーブルは全環境で共有（LockIDにキーパスが含まれるため競合しない） |
| **環境差分の吸収** | `terraform.tfvars` で環境固有値（インスタンスサイズ、desired_count、multi_az等）を切り替える |
| **モジュール内分岐禁止** | モジュール内で `var.env == "prod"` のような条件分岐は行わない。差分はすべて変数で注入する |

### 環境別パラメータ例（terraform.tfvars）

```
# dev
instance_class = "db.t4g.small"
desired_count  = 1
multi_az       = false

# prod
instance_class = "db.r7g.large"
desired_count  = 4
multi_az       = true
```


### Codex の成果物

以下の方針で設計する。

## 1. ディレクトリ構成

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
│   ├── ecs/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── security/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   ├── stg/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── providers.tf
│       ├── terraform.tfvars
│       └── variables.tf
└── bootstrap/
    ├── backend/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── README.md
```

## 2. モジュール分割方針

### `network`
責務:
- VPC
- Public / Private サブネット
- Internet Gateway
- NAT Gateway
- Route Table
- DB用サブネットグループの土台

補足:
- ALBはPublic Subnet
- ECS / RDSはPrivate Subnet

### `security`
責務:
- ALB用Security Group
- ECS用Security Group
- RDS用Security Group
- SG間通信ルールの整理

補足:
- `alb -> ecs`
- `ecs -> rds`
を明示する

### `alb`
責務:
- ALB
- Target Group
- Listener
- 必要に応じてListener Rule

補足:
- ECS Serviceがぶら下がるTarget Groupを出力する

### `ecs`
責務:
- ECS Cluster
- Task Definition
- ECS Service
- CloudWatch Logs
- Task Execution Role / Task Role
- Fargate設定

補足:
- ALB Target Group ARNを受け取る
- Private Subnet上に配置する

### `rds`
責務:
- RDS PostgreSQL
- DB Subnet Group
- Parameter Group
- Option Group（必要時）
- Backup / Multi-AZ / Storage設定

補足:
- DBパスワードは `tfvars` 直書きではなく Secrets Manager や SSM 参照を推奨

### `environments/dev|stg|prod`
責務:
- 各環境のルートモジュール
- モジュール呼び出し
- 環境別変数定義
- backend設定

### `bootstrap/backend`
責務:
- Terraform backend用のS3バケット
- DynamoDBロックテーブル
- 初期構築専用

## 3. 主要な変数・出力値の定義

代表例のみ示す。

### `modules/network/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_app_subnet_cidrs" {
  type = list(string)
}

variable "private_db_subnet_cidrs" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}
```

### `modules/network/outputs.tf`

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}
```

---

### `modules/security/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_ingress_cidrs" {
  type = list(string)
  default = ["0.0.0.0/0"]
}

variable "app_port" {
  type = number
  default = 80
}

variable "db_port" {
  type = number
  default = 5432
}
```

### `modules/security/outputs.tf`

```hcl
output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ecs_sg_id" {
  value = aws_security_group.ecs.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
```

---

### `modules/alb/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "listener_port" {
  type    = number
  default = 80
}

variable "target_port" {
  type    = number
  default = 80
}
```

### `modules/alb/outputs.tf`

```hcl
output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}
```

---

### `modules/ecs/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "container_name" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 80
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}
```

### `modules/ecs/outputs.tf`

```hcl
output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}
```

---

### `modules/rds/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_db_subnet_ids" {
  type = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "engine_version" {
  type    = string
  default = "15"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}
```

### `modules/rds/outputs.tf`

```hcl
output "db_instance_endpoint" {
  value = aws_db_instance.this.address
}

output "db_instance_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}
```

---

### `environments/dev/main.tf`

```hcl
module "network" {
  source                   = "../../modules/network"
  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  availability_zones       = var.availability_zones
}

module "security" {
  source       = "../../modules/security"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.network.vpc_id
  app_port     = var.app_port
  db_port      = var.db_port
}

module "alb" {
  source            = "../../modules/alb"
  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  target_port       = var.app_port
}

module "ecs" {
  source                = "../../modules/ecs"
  project_name          = var.project_name
  environment           = var.environment
  private_subnet_ids    = module.network.private_app_subnet_ids
  ecs_sg_id             = module.security.ecs_sg_id
  target_group_arn      = module.alb.target_group_arn
  container_name        = var.container_name
  container_image       = var.container_image
  container_port        = var.app_port
  desired_count         = var.desired_count
  environment_variables = var.app_environment_variables
}

module "rds" {
  source                = "../../modules/rds"
  project_name          = var.project_name
  environment           = var.environment
  private_db_subnet_ids = module.network.private_db_subnet_ids
  rds_sg_id             = module.security.rds_sg_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
}
```

## 4. Terraformステート管理方針

### バックエンド構成
推奨は `S3 + DynamoDB`。

- S3:
  - Terraform state 保存先
  - バージョニング有効化
  - SSE有効化
  - パブリックアクセス禁止
- DynamoDB:
  - State lock 用
  - 同時実行防止
- bootstrapで先にbackend基盤を作る

### `backend.tf` 例

```hcl
terraform {
  backend "s3" {
    bucket         = "myproj-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "myproj-terraform-lock"
    encrypt        = true
  }
}
```

### 環境分離戦略
基本は `dev / stg / prod` をディレクトリ分離する。

- `environments/dev`
- `environments/stg`
- `environments/prod`

分離対象:
- stateファイル
- tfvars
- resource naming
- スケール設定
- RDSサイズやMulti-AZ有無

`key` も環境ごとに分離する。

```text
dev/terraform.tfstate
stg/terraform.tfstate
prod/terraform.tfstate
```

### 命名規則
各リソース名に `project_name` と `environment` を含める。

例:
- `myapp-dev-alb`
- `myapp-stg-ecs`
- `myapp-prod-rds`

### 運用上の推奨
- `prod` は apply 権限を制限する
- `prod` は RDS `multi_az = true` を推奨
- 機密値は `terraform.tfvars` ではなく Secrets Manager / SSM を使う
- moduleは共通化し、差分は `tfvars` で吸収する

必要なら次に、これをそのまま使える `main.tf` のひな形一式まで落として出せる。

### Claude Code による評価

### 成果物A 評価

- **正確性: ★4** / 要件（VPC/ALB/ECS/RDS）を網羅し、モジュール間の依存関係も正しい。ただしECSとRDSの間に循環参照がある（`rds`が`module.ecs.ecs_security_group_id`を参照し、`ecs`が`module.rds.db_secret_arn`を参照）ため、そのままでは`terraform plan`が失敗する。
- **安全性: ★5** / DB認証情報をSecrets Managerで管理、S3バケットの暗号化・パブリックアクセスブロック・バージョニングをすべて設定。`deletion_protection`のデフォルトもtrueで本番事故を防止している。
- **可読性: ★5** / 各モジュールのvariables/outputsにdescriptionが付与され、モジュール分割方針・環境分離戦略が表形式で整理されており非常に読みやすい。「モジュール内分岐禁止」等の設計原則も明文化されている。
- **ベストプラクティス: ★4** / 環境×モジュールの構成、変数による差分注入、ステート分離はベストプラクティスに沿っている。循環参照の問題を除けば優秀。`az_count`からサブネットCIDRを自動算出する設計も柔軟性が高い。
- **総合コメント:** 完成度が高く、運用を見据えた設計。最大の問題点はECS⇔RDS間の循環参照で、securityモジュールの分離またはSG定義の移動で解消する必要がある。

---

### 成果物B 評価

- **正確性: ★4** / 3層構成を正しくカバーし、securityモジュールの独立によりSG間の循環参照を回避している。一方、`db_password`をvariableとして`sensitive = true`で受け取る設計は、tfvarsやCLI引数経由での渡し方次第でステートファイルに平文保存されるリスクがあり、Secrets Manager/SSM直接参照に比べると技術的に弱い。
- **安全性: ★3** / 運用推奨として「機密値はSecrets Manager/SSMを使う」と記載しているが、実装レベルでは`db_password`をvariableで受け取っており矛盾している。ステートファイルにパスワードが残る設計は安全性に課題がある。また、S3バックエンドの具体的な暗号化・アクセスブロック設定がbootstrapモジュールに記載されていない。
- **可読性: ★4** / モジュール責務の説明が箇条書きで整理されており理解しやすい。ただしvariablesにdescriptionがほぼ無く、`this`命名のリソース名だけでは意図が読み取りにくい箇所がある。
- **ベストプラクティス: ★4** / securityモジュールの分離はSG管理のベストプラクティスとして妥当。サブネットCIDRを明示的にlist(string)で渡す設計は透明性が高い。`providers.tf`の分離も良い。命名規則の明示も実用的。
- **総合コメント:** securityモジュール分離というアーキテクチャ判断は優れており、循環参照の問題を構造的に回避している。しかしDB認証情報の扱いが設計方針と実装で矛盾しており、bootstrapの具体実装も不足している。

---

### 最終判定

**成果物Aが総合的に優れている。**

理由:
1. **安全性の実装一貫性**: AはSecrets Managerを実装レベルで組み込んでおり、Bは推奨と記載しつつ`db_password`をvariableで受け取るという矛盾がある。IaCにおいてセキュリティは設計意図だけでなく実装で担保すべき。
2. **バックエンド基盤の具体性**: AはS3バケットの暗号化・パブリックアクセスブロック・バージョニングを具体的なHCLで示しているが、Bは箇条書きの方針のみ。
3. **設計原則の明文化**: 「モジュール内分岐禁止」「ライフサイクルとチーム責務の境界で分割」等、チーム開発で重要な原則がAには明記されている。

ただしAには**ECS⇔RDS間の循環参照**という構造的欠陥があり、Bのsecurityモジュール分離アプローチはこれを正しく解決している。Aの設計にBのsecurityモジュール分離を取り入れれば、より堅牢な設計になる。


### Codex による評価

### 成果物A 評価
- 正確性: ★2 / モジュール分割やステート管理の方針は概ね妥当ですが、`module "rds"` が `module.ecs.ecs_security_group_id` に依存しつつ、`module "ecs"` が `module.rds.db_secret_arn` に依存しており、ルートで循環依存になります。設計説明としてはよく整理されていますが、このままでは `plan/apply` できません。
- 安全性: ★4 / DB認証情報を Secrets Manager に逃がす方針、backend の S3 暗号化・Public Access Block は良いです。ただし ECS が Secret を読むための IAM 権限や、ALB の HTTP/HTTPS 強制方針が明示されておらず、詰め切れていません。
- 可読性: ★4 / 章立て、責務分割、変数・出力の例が揃っており、読み手が全体像を追いやすいです。一方で依存関係のねじれが文面からは見抜きにくく、設計の整合性確認が甘いです。
- ベストプラクティス: ★3 / `environments` と `modules` の分離、backend bootstrap 分離、環境差分を `tfvars` で吸収する方針は Terraform 的に素直です。ただし SG を各モジュールに持たせつつ cross-module で参照させているため依存が複雑化しており、設計としてはやや崩れています。
- 総合コメント: セキュリティ意識と構成整理は比較的良いですが、循環依存という致命的な設計不備があります。レビュー観点では「よく考えているが、実装可能性の最後の詰めで落としている」成果物です。

### 成果物B 評価
- 正確性: ★4 / 3層 Web アプリの典型構成として素直で、特に `security` モジュールを切り出して `alb -> ecs -> rds` の通信を整理している点は実装しやすいです。細部の不足はありますが、少なくとも A のような循環依存は見当たりません。
- 安全性: ★3 / `db_password` を `sensitive = true` にしているのは最低限の配慮ですが、変数として受ける設計自体は state に残るため十分ではありません。本文で Secrets Manager / SSM を推奨している一方、モジュール I/F がそれを前提にしていないため、設計と実装方針が少しずれています。
- 可読性: ★4 / 責務ごとの説明が簡潔で、変数名も `project_name`、`private_app_subnet_ids` など意図が明確です。A ほど詳細ではないものの、構成の追いやすさは高いです。
- ベストプラクティス: ★4 / SG を独立モジュールに寄せて依存を単純化している点、環境ごとの root module 分離、bootstrap 分離は良いです。反面、provider version 制約や `required_providers`/`required_version` の視点、秘密情報の受け渡し設計まで踏み込めていないため満点ではありません。
- 総合コメント: 実装に落とし込みやすい設計で、Terraform のモジュール境界も比較的きれいです。セキュリティ面の詰めは甘いですが、全体としては破綻が少なく、現実的です。

### 最終判定
総合的には **B の方が優れています**。最大の理由は、A には `ecs` と `rds` の間に循環依存という致命的な実装不能ポイントがあるのに対し、B は多少粗くても構成が素直で、そのまま詳細実装に進めやすいからです。

A は Secrets Manager を使うなど安全性の方向性は良いですが、Terraform 設計としては依存関係の整理に失敗しています。B は秘密情報の扱いに改善余地があるものの、モジュール責務と依存方向が比較的健全で、IaC としての完成度は B が上です。

---

## コード生成

### Claude Code の成果物

```hcl:versions.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

```hcl:variables.tf
variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of two availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

```hcl:main.tf
################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.azs[count.index]}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# NAT Gateway (single, cost-optimized)
################################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.azs[count.index]}"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private"
  })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

```hcl:outputs.tf
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.this.id
}
```

**設計ポイント:**

- **NAT Gateway 1個**: 両プライベートサブネットが同一のルートテーブルを共有し、単一のNAT Gatewayを経由。コスト優先の構成
- **ルートテーブル**: パブリック用（IGW向け）1つ、プライベート用（NAT向け）1つ。それぞれ2サブネットに関連付け
- **タグ**: 全リソースで `merge(var.tags, { Name = "..." })` を使用し、呼び出し側からのタグとリソース固有のNameタグを統合
- **`depends_on`**: NAT GatewayにIGWへの明示的依存を設定（AWS要件）


### Codex の成果物

シェル/編集ツールがこの環境では実行不可だったため、要件を満たす4ファイルの内容をそのまま示します。

```hcl:main.tf
locals {
  common_tags = merge(var.tags, {
    Module = "vpc"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = var.name
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-rt"
  })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

```hcl:variables.tf
variable "name" {
  description = "Name prefix for VPC resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "Two availability zones used by the public and private subnets."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly 2 AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "Two CIDR blocks for the public subnets."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "Two CIDR blocks for the private subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
```

```hcl:outputs.tf
output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway."
  value       = aws_nat_gateway.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table."
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

- **正確性: ★4** / VPC・サブネット・NAT Gateway・ルートテーブルの構成は技術的に正しい。ただし `count = 2` がハードコードされており、`var.public_subnets` や `var.azs` の長さが2でない場合に実行時エラーとなる不整合がある。
- **安全性: ★4** / DNS設定有効化、NAT Gateway経由のプライベートサブネット構成など基本的なセキュリティ要件を満たす。VPC Flow LogsやネットワークACLの明示的設定はないが、モジュールの責務としては許容範囲。
- **可読性: ★5** / セクション区切りのコメント(`####`)が明瞭で、設計ポイントのドキュメントも付属しており意図が非常に分かりやすい。サブネットのNameタグにAZ名を含めている点も運用上有用。
- **ベストプラクティス: ★3** / `count = 2` のハードコードは `length(var.public_subnets)` とすべき。`var.cidr` にデフォルト値があるのは便利だが、variableのvalidationブロックが無く入力値の誤りを防げない。`versions.tf` の `>= 5.0` はメジャーバージョンアップで破壊的変更を受ける可能性がある。
- **総合コメント:** 構造が明快で読みやすく、設計意図のドキュメントも優れている。一方、countのハードコードとvalidation不足が実運用上のリスク。

---

### 成果物B 評価

- **正確性: ★5** / `length()` による動的count、variableのvalidationブロックで入力値を厳密に検証しており、技術的に堅牢。全リソースの接続関係も正しい。
- **安全性: ★4** / Aと同等のネットワーク構成で基本的な安全性を確保。`Tier` タグの付与はセキュリティグループやNACLのポリシー適用時に有用。
- **可読性: ★4** / `local.common_tags` による共通タグの抽象化は良いが、セクション区切りコメントがなくリソースが連続しているため、Aに比べると一覧性がやや劣る。サブネット名が `count.index + 1` の数値のみでAZ名を含まないため、運用時の識別性がわずかに低い。
- **ベストプラクティス: ★5** / `length()` による動的count、validationブロック、`local` による共通タグの集約、`~> 5.0` によるマイナーバージョン固定、ルートテーブルIDのoutput公開など、Terraformのベストプラクティスに忠実。
- **総合コメント:** 防御的プログラミングが徹底されており、モジュールとしての堅牢性が高い。可読性はやや地味だが、実運用での安定性を重視した設計。

---

### 最終判定

**成果物Bが総合的に優れている。**

最大の差は以下の2点:

1. **Validationブロック**: Bは `availability_zones`、`public_subnet_cidrs`、`private_subnet_cidrs` すべてに長さ検証を入れており、`terraform plan` 時点で不正入力を検出できる。Aは `count = 2` をハードコードしながらvariableの長さを制約していないため、リスト長の不一致でわかりにくいエラーが発生しうる。
2. **プロバイダバージョン制約**: Aの `>= 5.0` はメジャーバージョン6以降でも許容してしまうが、Bの `~> 5.0` はパッチ・マイナーのみ許容し破壊的変更を防ぐ。これはTerraformの推奨パターンに合致する。

Aの方が可読性・ドキュメント面では優れているため、チーム内での説明資料としてはAが向いている場面もあるが、**モジュールとしての品質**はBが一段上。


### Codex による評価

### 成果物A 評価
- 正確性: ★4 / VPC、2つのパブリックサブネット、2つのプライベートサブネット、IGW、単一NAT、ルートテーブル関連付けまで一通り成立しており、構成としては要件を概ね満たしています。 ただし `count = 2` の固定や入力値の整合性検証がないため、`azs` や CIDR リストの長さ不一致時に壊れやすいです。
- 安全性: ★3 / 重大なセキュリティ事故につながる設定は見当たりませんが、公開サブネットで `map_public_ip_on_launch = true` を有効化しており、誤って公開用EC2を載せた場合の露出余地はあります。 また、入力CIDRの妥当性や重複防止の検証がなく、安全側に倒した実装ではありません。
- 可読性: ★4 / ファイル分割とセクションコメントが明快で、Terraformに慣れた人なら読みやすい構成です。 一方で `count.index` 前提の実装が全体に散っており、入力配列との対応関係を読む側が追う必要があります。
- ベストプラクティス: ★3 / タグの `merge`、出力定義、責務ごとのファイル分割は良いです。 ただし Provider を `>= 5.0` で広く許容している点、入力値 validation がない点、固定 `count = 2` による拡張性の低さは、Terraform実務の観点では弱いです。
- 総合コメント: 動く構成としては十分ですが、堅牢性と保守性を高めるための入力検証とバージョン制約が不足しています。 最小実装としては悪くない一方、運用を見据えるとやや粗いです。

### 成果物B 評価
- 正確性: ★5 / Aと同じく必要なAWSネットワーク部品を過不足なく揃えており、構成意図も一貫しています。 加えて AZ 数とサブネットCIDR数に validation を入れており、前提条件をコードで担保している分、実運用での正確性が高いです。
- 安全性: ★4 / A同様、公開サブネットでの自動パブリックIP付与はありますが、要件上は妥当な範囲です。 少なくとも入力検証により誤配線や不整合な構成を防ぎやすくしており、安全面ではAより一段良いです。
- 可読性: ★4 / `locals.common_tags` によるタグ集約、変数名の明確さ、出力の説明文などで理解しやすく整理されています。 ただし `count` ベースの実装は残っており、`for_each` ほどの自己記述性はありません。
- ベストプラクティス: ★4 / `~> 5.0` によるProvider制約、変数 validation、共通タグの `locals` 化はTerraformらしい堅実な書き方です。 モジュール分割や `for_each` 活用まで踏み込んでいないため満点ではないものの、Aより明確に良いです。
- 総合コメント: 実装内容自体はAと近いですが、入力前提の明文化とバージョン管理ができており、壊れにくさと保守性で上回ります。 実務でレビューを通しやすいのはこちらです。

### 最終判定
総合的には **Bのほうが優れています**。

理由は、構成の中身はA/Bとも大差ない一方で、Bは `validation` によって入力前提をコード化し、Provider も `~> 5.0` でより安全に固定しているためです。 Aは「動くTerraform」としては十分ですが、Bのほうが Terraform の実務的な堅牢性と保守性により配慮できています。

---

## レビュー

### Claude Code の成果物

## Terraformコードレビュー結果

### 問題一覧

**セキュリティグループ (`aws_security_group.web`)**

- [CRITICAL] `aws_security_group.web` ingress : 全ポート(0-65535)を全世界(0.0.0.0/0)に開放しており、攻撃対象面が最大化されている -> 必要なポート(例: 443, 80)のみに限定し、送信元もCloudFront Prefix ListやALBのSGに制限する
- [MEDIUM] `aws_security_group.web` egress : 全方向へのアウトバウンドが無制限に許可されている -> データ流出リスク軽減のため、必要な宛先・ポートのみ許可する（最低限NATゲートウェイ経由に制限）
- [LOW] `aws_security_group.web` : `description` が未設定 -> SGの用途を明示するために `description` を設定する

**RDSインスタンス (`aws_db_instance.main`)**

- [CRITICAL] `aws_db_instance.main` password : パスワードがハードコードされており、tfstateにも平文で保存される -> `aws_secretsmanager_secret` や変数(`sensitive = true`)で管理し、コードから除外する
- [CRITICAL] `aws_db_instance.main` publicly_accessible : RDSがインターネットから直接到達可能になっている -> `publicly_accessible = false` にし、プライベートサブネットに配置する
- [HIGH] `aws_db_instance.main` storage_encrypted : ストレージが暗号化されていないため、物理レベルでのデータ漏洩リスクがある -> `storage_encrypted = true` を設定し、KMSキーを指定する
- [HIGH] `aws_db_instance.main` username : 管理者ユーザー名が推測容易な `admin` -> 推測困難な名前に変更する
- [MEDIUM] `aws_db_instance.main` : `backup_retention_period` 未設定（デフォルト0=バックアップ無し） -> 最低7日間の自動バックアップを設定する
- [MEDIUM] `aws_db_instance.main` : `multi_az` 未設定で単一AZ構成 -> 本番環境では `multi_az = true` で可用性を確保する
- [MEDIUM] `aws_db_instance.main` : `deletion_protection` 未設定 -> 誤削除防止のため `deletion_protection = true` を設定する
- [LOW] `aws_db_instance.main` : `engine_version` 未指定で意図しないバージョンが選ばれる可能性がある -> 明示的にバージョンを指定する

**S3バケット (`aws_s3_bucket.data`)**

- [HIGH] `aws_s3_bucket.data` : サーバーサイド暗号化が未設定 -> `aws_s3_bucket_server_side_encryption_configuration` でSSE-S3またはSSE-KMSを設定する
- [HIGH] `aws_s3_bucket.data` : パブリックアクセスブロックが未設定 -> `aws_s3_bucket_public_access_block` で全項目 `true` に設定する
- [MEDIUM] `aws_s3_bucket.data` : バージョニングが未設定で誤削除時に復元不可 -> `aws_s3_bucket_versioning` を有効にする
- [MEDIUM] `aws_s3_bucket.data` : アクセスログが未設定 -> `aws_s3_bucket_logging` で監査ログを取得する
- [LOW] `aws_s3_bucket.data` : バケット名が静的でグローバル一意性が保証されにくい -> `account_id` やランダムサフィックスを含める

**全体構成**

- [MEDIUM] provider : `backend` 未設定でtfstateがローカル管理になる -> S3 + DynamoDBによるリモートバックエンドを設定する
- [MEDIUM] 全体 : タグが一切付与されていない -> コスト管理・運用のため `default_tags` または各リソースに共通タグを付与する
- [LOW] 全体 : `terraform { required_version }` および `required_providers` が未設定 -> バージョン制約を明示して再現性を担保する

---

### 最優先で直すべきTOP3

| 順位 | 対象 | 理由 |
|------|------|------|
| **1** | `aws_db_instance.main` の **パスワードハードコード** | tfstate含めあらゆる場所に平文で漏洩する。Secrets Manager等での管理が必須 |
| **2** | `aws_db_instance.main` の **publicly_accessible = true** | DBがインターネットに直接晒されており、上記のSG全開放と合わせて即座に攻撃対象になる |
| **3** | `aws_security_group.web` の **全ポート全世界開放** | 0-65535/tcp を 0.0.0.0/0 に開放しており、VPC内の全リソースが無防備になる |


### Codex の成果物

- [CRITICAL] `aws_db_instance.main` : `password = "password123"` のように認証情報をTerraformコードへ平文ハードコードしている -> `variable` + `sensitive = true` を使い、実値は `tfvars` ではなく Secrets Manager / SSM Parameter Store などの外部シークレット管理へ移す
- [CRITICAL] `aws_db_instance.main` : `publicly_accessible = true` によりDBがインターネット到達可能になり、侵害リスクが極めて高い -> `publicly_accessible = false` にし、private subnet内へ配置してアプリ用SGからのみ接続を許可する
- [CRITICAL] `aws_db_instance.main` : `storage_encrypted = false` でDB保存データが暗号化されない -> `storage_encrypted = true` を設定し、必要に応じてKMSキーを明示指定する
- [HIGH] `aws_security_group.web` : `ingress` が `0.0.0.0/0` かつ `0-65535/tcp` 全開放で、不要ポートまで世界公開されている -> 必要なポートのみ（例: `80`, `443`）に限定し、管理用アクセスも送信元CIDRや踏み台SGで絞る
- [HIGH] `aws_db_instance.main` : DB用の `vpc_security_group_ids` や `db_subnet_group_name` がなく、ネットワーク制御と配置先が不明確 -> 専用DBセキュリティグループとprivate subnet用のDB subnet groupを明示する
- [HIGH] `aws_db_instance.main` : `skip_final_snapshot = true` により削除時に最終バックアップが残らず、障害・誤削除時の復旧性が低い -> 本番系では `skip_final_snapshot = false` にし、`final_snapshot_identifier` を設定する
- [MEDIUM] `aws_s3_bucket.data` : バケットに暗号化設定、パブリックアクセスブロック、バージョニング等の最低限の保護設定がない -> `server_side_encryption_configuration`、`aws_s3_bucket_public_access_block`、`versioning` を追加する
- [MEDIUM] `aws_s3_bucket.data` : `bucket = "my-app-data-bucket"` はグローバル一意制約のため環境間衝突や作成失敗を招きやすい -> 環境名やアカウントIDを含めた命名規則に変更する
- [MEDIUM] `aws_db_instance.main` : `username = "admin"` の固定利用は推測されやすく、運用上も好ましくない -> 汎用名を避け、ユーザー名も変数化し、認証方式全体をSecrets Manager連携前提にする
- [MEDIUM] `aws_vpc.main` / 全体 : VPCはあるがsubnet、route table、NAT/IGWなどの周辺設計がなく、実運用可能な閉域/公開分離構成になっていない -> public/private subnetを分離し、WebとDBで配置レイヤを分ける
- [LOW] `provider "aws"` : provider version pinningがなく、将来のprovider更新で挙動差分が出る -> `required_providers` とバージョン制約を `terraform` ブロックで明示する
- [LOW] `全体` : タグ設計がなく、運用管理・課金分析・棚卸しがしづらい -> `Name`, `Environment`, `Owner`, `CostCenter` などの共通タグを全リソースへ付与する

最優先で直すべきTOP3

1. `aws_db_instance.main` の平文パスワード廃止とSecrets Manager/SSMへの移行
2. `aws_db_instance.main` の `publicly_accessible = true` をやめてprivate配置に変更
3. `aws_security_group.web` の全TCP全世界開放を必要最小限のポート・送信元に制限

### Claude Code による評価

### 成果物A 評価

- **正確性: ★5** / 指摘内容はすべて技術的に正しく、SGの全ポート開放、RDSのパスワードハードコード・publicly_accessible、S3の暗号化未設定など、要件を漏れなく網羅している。egress制限やbackup_retention_period、deletion_protection、engine_versionなど細かい点まで拾えている。
- **安全性: ★5** / CRITICALからLOWまでの重要度分類が適切で、修正方針も具体的（Secrets Manager、KMS、CloudFront Prefix List等）。セキュリティ観点の見落としはほぼない。
- **可読性: ★5** / リソース単位でセクション分けし、`[CRITICAL]`等のラベル付きで一覧化、さらにTOP3を表形式でまとめており、読み手が即座に優先順位を判断できる構成。
- **ベストプラクティス: ★5** / `required_version`/`required_providers`未設定、`backend`未設定、`default_tags`未設定など、Terraformの運用ベストプラクティスに沿った指摘が充実している。egress制限やdescription設定など細部まで行き届いている。
- **総合コメント:** 網羅性・構造化・具体性の三拍子が揃っている。リソース別にセクションを分け、全体構成の指摘も独立セクションとして整理しており、レビュー文書としての完成度が高い。

---

### 成果物B 評価

- **正確性: ★4** / 主要な問題はすべて正しく指摘しており、Aにない指摘として`vpc_security_group_ids`/`db_subnet_group_name`の欠如、`skip_final_snapshot`のリスク、VPCの周辺設計不足（subnet/route table/NAT/IGW）など、実運用観点で有用な指摘がある。一方でAが拾っている`egress`制限、`backup_retention_period`、`deletion_protection`、`multi_az`、S3アクセスログ、`engine_version`への言及がない。
- **安全性: ★4** / `storage_encrypted = false`をCRITICALとしている点はAのHIGHより妥当性が高い判断とも言える。ただしS3関連の指摘がMEDIUMで1項目にまとめられており、パブリックアクセスブロック未設定の危険度がやや過小評価されている。
- **可読性: ★3** / フラットなリスト形式で全指摘が並んでおり、リソース別のセクション分けがない。指摘数が増えると全体像の把握が難しくなる。TOP3は簡潔だが表形式ではなく、Aと比べると一覧性で劣る。
- **ベストプラクティス: ★4** / provider version pinning、タグ設計、VPCのsubnet分離設計への言及がある点は良い。一方で`required_version`、`backend`設定、`description`設定など基本的なTerraformベストプラクティスへの言及が欠けている。
- **総合コメント:** 個々の指摘の質は高く、特にDB subnet groupやskip_final_snapshot、VPC周辺設計への言及はAにない実践的な視点。ただし構造化が不十分で、一部の基本的な指摘が抜けている。

---

### 最終判定

**成果物Aが総合的に優れている。**

理由: 両者ともコアとなるCRITICAL指摘（パスワードハードコード、publicly_accessible、SG全開放）は共通しており、技術的正確性に大きな差はない。しかしAは以下の点で明確に上回る。

1. **網羅性**: Aは19項目、Bは12項目。Aはegress制限、backup_retention_period、multi_az、deletion_protection、S3アクセスログ、engine_version、backend設定など、Bが見落としている指摘を複数含む。
2. **構造化**: Aはリソース単位のセクション分け＋全体構成セクション＋表形式のTOP3という三層構造で、レビュー文書としての完成度が高い。Bはフラットリストで可読性に劣る。
3. **修正方針の具体性**: Aは各指摘に対して具体的な設定値やAWSサービス名を挙げた改善案を示している。

一方でBにはAにない有用な指摘（`db_subnet_group_name`欠如、`skip_final_snapshot`、VPC周辺設計不足）もあり、実運用の観点では補完的な価値がある。理想的には両者の指摘を統合することで、より完全なレビューとなる。


### Codex による評価

### 成果物A 評価
- 正確性: ★4 / 指摘の大半は妥当で、SG全開放・RDS平文パスワード・公開RDS・S3保護不足など重要論点を適切に捉えています。ただし「egressは最低限NATゲートウェイ経由に制限」のように、一般論としてはやや雑で要件依存の表現もあります。
- 安全性: ★4 / 重大なセキュリティリスクを優先度付きで整理できており、実務上の危険箇所を見落としていません。一方で、RDSの `skip_final_snapshot` やDB用SG/サブネットグループ未定義のような復旧性・閉域性に直結する観点が抜けています。
- 可読性: ★5 / リソース単位で整理され、重要度ラベル、原因、改善案が一貫した形式で並んでいて非常に読みやすいです。最後のTOP3も表形式で要点が把握しやすいです。
- ベストプラクティス: ★4 / `required_version`、`required_providers`、タグ、remote backend まで触れており、Terraform運用の基本を押さえています。ただしS3まわりで現行のAWS providerでは専用リソース分離が前提になる点を踏まえると、記述粒度はやや粗めです。
- 総合コメント: レビューとしての構造がよく、優先順位も明確です。強い指摘は十分できていますが、ネットワーク閉域設計や削除保護・復旧設計の観点でもう一段踏み込める余地があります。

### 成果物B 評価
- 正確性: ★5 / 指摘内容が具体的で、RDSの平文パスワード、公開設定、暗号化無効、SG全開放、DB subnet groupやSG未定義、最終スナップショット無効など、実装上の危険点をより直接的に捉えています。構成不足が「実運用可能か」という観点まで踏み込めているのも良いです。
- 安全性: ★5 / セキュリティ上の優先度付けが適切で、特にDBの閉域配置、専用SG、シークレット外部化まで具体策が明確です。暗号化、公開面、削除時保護の指摘もあり、Aより防御面の網羅性が高いです。
- 可読性: ★4 / 箇条書き中心で十分読みやすいですが、Aのようなリソース別セクション整理や表形式の視認性には一歩劣ります。ただし各指摘が具体的で、改善アクションまで直結している点は優秀です。
- ベストプラクティス: ★5 / `required_providers`、タグ設計だけでなく、private subnet分離、DB subnet group、SG境界、Secrets Manager/SSM連携など、Terraformで表現すべき実運用設計に踏み込めています。IaCとしての責務範囲をより適切に捉えています。
- 総合コメント: 単なる静的な危険指摘に留まらず、AWS/Terraformで本来あるべき構成まで示せており、レビューの質が高いです。体裁はAの方が整っていますが、内容の深さと実務性はBが上です。

### 最終判定
**Bの方が総合的に優れています。**

理由は、Aもよくまとまっていますが、Bは「危険な設定がある」だけでなく、「なぜ実運用上成立しないか」「Terraformでどこまで明示すべきか」まで踏み込めているためです。特に `db_subnet_group_name` や `vpc_security_group_ids`、`skip_final_snapshot`、VPC周辺設計不足への指摘は、IaCレビューとしてAより実践的で、正確性・安全性・ベストプラクティス準拠の3軸で一段上です。

---
