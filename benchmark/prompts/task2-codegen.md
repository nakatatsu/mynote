以下の要件を満たすTerraform VPCモジュールを実装せよ。

## 要件

- パブリックサブネット × 2（マルチAZ）
- プライベートサブネット × 2（マルチAZ）
- Internet Gateway
- NAT Gateway 1個（パブリックサブネットに配置、コスト優先）
- 適切なルートテーブル設定

## 制約

- Terraform >= 1.0
- AWSプロバイダーバージョンを `versions.tf` で明示すること
- 以下の4ファイル構成で実装すること:
  - `main.tf`
  - `variables.tf`
  - `outputs.tf`
  - `versions.tf`
- `var.tags` を受け取り、全リソースで `merge` してタグを付与すること
- リソースに適切なタグを付与すること

## 出力形式

各ファイルの内容を以下の形式で出力すること。

` ```hcl:main.tf `
（内容）
` ``` `

` ```hcl:variables.tf `
（内容）
` ``` `

` ```hcl:outputs.tf `
（内容）
` ``` `

` ```hcl:versions.tf `
（内容）
` ``` `
