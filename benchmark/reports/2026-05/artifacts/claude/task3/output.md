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
