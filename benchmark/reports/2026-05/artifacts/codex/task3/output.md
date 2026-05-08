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