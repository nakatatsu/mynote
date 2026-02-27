- [CRITICAL] `aws_security_group.web.ingress` : `0.0.0.0/0` に対して `tcp 0-65535` を全面開放しており、全ポートがインターネット公開される -> 必要最小限のポート（例: 80/443）のみに絞り、送信元CIDRも限定する
- [CRITICAL] `aws_db_instance.main.password` : DBパスワードを平文でコードに直書きしており漏洩リスクが高い -> `variable` + `sensitive = true` を使い、AWS Secrets Manager/SSM Parameter Store から参照する
- [HIGH] `aws_db_instance.main.publicly_accessible` : RDSがパブリックアクセス可能で外部攻撃面が拡大している -> `publicly_accessible = false` にし、Private Subnet + 厳格なSecurity Group経由のみにする
- [HIGH] `aws_db_instance.main.storage_encrypted` : RDS暗号化が無効で保存データ保護要件を満たせない -> `storage_encrypted = true`（必要に応じてKMSキー指定）にする
- [HIGH] `aws_db_instance.main.skip_final_snapshot` : 削除時に最終スナップショットを取得せず復旧不能リスクがある -> `skip_final_snapshot = false` とし `final_snapshot_identifier` を設定する
- [HIGH] `aws_s3_bucket.data` : バケット暗号化・公開ブロック・バージョニングが未設定で、漏洩/改ざん/復旧性のリスクがある -> `server_side_encryption_configuration`、`aws_s3_bucket_public_access_block`、`versioning` を追加する
- [MEDIUM] `aws_db_instance.main` : バックアップ保持期間や削除保護が未設定で運用事故耐性が低い -> `backup_retention_period` と `deletion_protection` を有効化する
- [MEDIUM] `provider "aws"` : Providerバージョン固定がなく再現性が低い -> `required_providers` でAWS Providerのバージョン制約を明示する
- [LOW] `aws_s3_bucket.data.bucket` : 固定名はグローバル一意衝突や環境間競合を起こしやすい -> 接頭辞/サフィックス（環境名・アカウントID等）を付与して一意化する

最優先で直すべきTOP3
1. `aws_security_group.web.ingress` の全ポート全開放を即時停止（最小権限化）
2. `aws_db_instance.main.password` の平文管理を廃止（Secrets Manager/SSM化）
3. `aws_db_instance.main.publicly_accessible = true` を無効化してRDSをプライベート配置