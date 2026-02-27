以下のTerraformコードをレビューせよ。

## 出力形式（厳守）

問題点と改善提案を以下のフォーマットで出力すること。

```
- [CRITICAL|HIGH|MEDIUM|LOW] <対象リソース/箇所> : <問題> -> <改善案>
```

最後に「最優先で直すべきTOP3」を列挙すること。

## レビュー対象コード

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
