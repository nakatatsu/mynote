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
