#!/usr/bin/env python3
"""Generate benchmark result.md from evaluation artifacts."""
import json
import sys
from pathlib import Path


def load(path: Path) -> str:
    return path.read_text() if path.exists() else "(未取得)"


def generate(report_dir: str) -> None:
    d = Path(report_dir)
    mapping = json.loads((d / "ab-mapping.json").read_text())

    claude_score_file = d / "artifacts/claude/task2/score.json"
    codex_score_file = d / "artifacts/codex/task2/score.json"
    claude_score = json.loads(claude_score_file.read_text()) if claude_score_file.exists() else {"task2_score": "-"}
    codex_score = json.loads(codex_score_file.read_text()) if codex_score_file.exists() else {"task2_score": "-"}

    lines = [
        f"# Benchmark Result {d.name}\n",
        "## スコアサマリー\n",
        "| タスク | Claude Code | Codex |",
        "|--------|------------|-------|",
        f"| タスク2（自動評価） | {claude_score['task2_score']}/4 | {codex_score['task2_score']}/4 |",
        "| タスク1・3 | (相互評価参照) | (相互評価参照) |\n",
        f"A={mapping['A']}, B={mapping['B']}（評価時のブラインド割り当て）\n",
        "---\n",
    ]

    for task, label in [("task1", "設計"), ("task2", "コード生成"), ("task3", "レビュー")]:
        lines += [
            f"## {label}\n",
            "### Claude Code の成果物\n",
            load(d / "artifacts/claude" / task / "output.md"),
            "\n### Codex の成果物\n",
            load(d / "artifacts/codex" / task / "output.md"),
            "\n### Claude Code による評価\n",
            load(d / f"artifacts/eval-by-claude-{task}.md"),
            "\n### Codex による評価\n",
            load(d / f"artifacts/eval-by-codex-{task}.md"),
            "\n---\n",
        ]

    result_path = d / "result.md"
    result_path.write_text("\n".join(lines))
    print(f"Generated: {result_path}")


if __name__ == "__main__":
    generate(sys.argv[1])
