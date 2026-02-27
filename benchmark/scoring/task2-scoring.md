# タスク2 採点基準（4点満点）

※ Issueには記載しない。自動評価スクリプト（eval-task2.sh）が判定する。

各ツールの終了コードが 0 の場合に1点を加算する。

| # | ツール | コマンド | 配点 |
|---|--------|---------|------|
| 1 | terraform fmt | `terraform fmt -check -recursive <dir>` | 1点 |
| 2 | terraform validate | `terraform init && terraform validate` | 1点 |
| 3 | tflint | `tflint --init && tflint -f compact` | 1点 |
| 4 | checkov | `checkov -d <dir> --framework terraform` | 1点 |

**合計: /4**

## 備考

- terraform validate はネットワーク接続が必要（AWSプロバイダーのダウンロード）
- tflint は初回実行時に GitHub API を使いAWSプラグインをダウンロードする
- checkov はセキュリティ問題を1件でも検出すると終了コード1を返す（0点）
