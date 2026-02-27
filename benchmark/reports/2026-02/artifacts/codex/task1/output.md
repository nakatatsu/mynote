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