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