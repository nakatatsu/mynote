#!/usr/bin/env python3
"""Extract HCL code blocks from markdown output."""
import re
import sys
from pathlib import Path


def extract(input_file: str, output_dir: str) -> None:
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    text = Path(input_file).read_text()
    pattern = re.compile(r'```hcl:(\S+)\n(.*?)```', re.DOTALL)
    for match in pattern.finditer(text):
        filename, content = match.group(1), match.group(2)
        (Path(output_dir) / filename).write_text(content)
        print(f"Extracted: {filename}")


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
