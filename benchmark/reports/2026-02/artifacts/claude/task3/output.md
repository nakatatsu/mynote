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
