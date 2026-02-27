# タスク3 採点基準（正解重大度表）

※ Issueには記載しない。採点者のみが使用する。

## 仕込んだ問題と正解重大度

| # | 対象リソース/箇所 | 問題 | 正解重大度 |
|---|-----------------|------|-----------|
| 1 | `aws_security_group.web` | 全ポート（0-65535）全開放 | CRITICAL |
| 2 | `aws_db_instance.main` | パスワードのハードコード（Secrets Manager等を使うべき） | CRITICAL |
| 3 | `aws_db_instance.main` | `publicly_accessible = true`（DBをパブリック公開） | CRITICAL |
| 4 | `aws_db_instance.main` | `storage_encrypted = false`（暗号化無効） | HIGH |
| 5 | `aws_db_instance.main` | `skip_final_snapshot = true`（スナップショットなし） | HIGH |
| 6 | `aws_s3_bucket.data` | パブリックアクセスブロック未設定 | HIGH |
| 7 | 全リソース | タグ付与なし | MEDIUM |

## 採点手順

### 指摘ヒット数（/7点）

モデルの出力を確認し、上記7問題のうち何件を指摘しているかを数える。
- 指摘内容が問題の本質を捉えていれば「ヒット」とする
- 表現が異なっても意味が合っていればヒットとして扱う

### 重大度判定の正確さ

ヒットした問題について、正解重大度と一致しているかを確認する。
- CRITICAL/HIGH/MEDIUM/LOWの1段階以内のずれは許容する

### TOP3 評価

最優先TOP3にCRITICAL問題（#1〜#3）がすべて含まれていれば満点とする。
2件含まれていれば部分点、1件以下は0点。
