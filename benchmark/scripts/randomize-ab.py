#!/usr/bin/env python3
"""Randomly assign claude/codex artifacts to A/B labels."""
import json
import random
import sys
from pathlib import Path


def randomize(report_dir: str) -> None:
    models = ["claude", "codex"]
    random.shuffle(models)
    mapping = {"A": models[0], "B": models[1]}
    out = Path(report_dir) / "ab-mapping.json"
    out.write_text(json.dumps(mapping, indent=2))
    print(f"A={mapping['A']}, B={mapping['B']}")


if __name__ == "__main__":
    randomize(sys.argv[1])
