#!/usr/bin/env python3
"""Write docs/schools.json for the site from the bundled school index.

The app ships its adapters inside assets/warehouse/, so that bundled index is
the single source of truth for which schools are supported. Nothing is fetched
over the network.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

BUNDLED_INDEX = Path("assets/warehouse/root_index.yaml")
DEFAULT_OUTPUT = Path("docs/schools.json")

QUOTED_VALUE = re.compile(r'^[^:\s]+:\s*["\']?(.+?)["\']?\s*$')


def extract_value(line: str) -> str:
    without_comment = re.sub(r"\s+#.*$", "", line.strip())
    match = QUOTED_VALUE.match(without_comment)
    if not match:
        return ""
    return match.group(1).strip()


def parse_root_index_yaml(text: str) -> list[dict[str, str]]:
    schools: list[dict[str, str]] = []
    current: dict[str, str] | None = None

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped.startswith("- id:"):
            if current:
                schools.append(current)
            current = {"id": extract_value(stripped.removeprefix("- ").strip())}
            continue

        if current is None:
            continue

        for key in ("name", "initial", "resource_folder"):
            if stripped.startswith(f"{key}:"):
                current[key] = extract_value(stripped)
                break

    if current:
        schools.append(current)

    return [
        item
        for item in schools
        if item.get("id") and item.get("name") and item.get("resource_folder")
    ]


def classify_school(entry: dict[str, str]) -> str:
    school_id = entry["id"]
    name = entry["name"]
    if school_id == "GLOBAL_TOOLS" or "通用" in name:
        return "generic"
    return "school"


def sort_key(entry: dict[str, str]) -> tuple[int, str, str]:
    category = classify_school(entry)
    generic_rank = 0 if category == "generic" else 1
    return (generic_rank, entry.get("initial", ""), entry.get("name", ""))


def build_payload(entries: list[dict[str, str]], source: str) -> dict:
    normalized = []
    for entry in sorted(entries, key=sort_key):
        normalized.append(
            {
                "id": entry["id"],
                "name": entry["name"],
                "initial": entry.get("initial", ""),
                "resourceFolder": entry["resource_folder"],
                "category": classify_school(entry),
            }
        )

    school_count = sum(1 for item in normalized if item["category"] == "school")
    generic_count = sum(1 for item in normalized if item["category"] == "generic")

    return {
        "updatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "source": source,
        "counts": {
            "total": len(normalized),
            "schools": school_count,
            "generic": generic_count,
        },
        "schools": normalized,
    }


def main() -> int:
    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    index_path = Path(sys.argv[2]) if len(sys.argv) > 2 else BUNDLED_INDEX

    if not index_path.is_file():
        print(f"ERROR: bundled school index not found: {index_path}", file=sys.stderr)
        return 1

    entries = parse_root_index_yaml(index_path.read_text(encoding="utf-8"))
    if not entries:
        print(f"ERROR: no schools parsed from {index_path}", file=sys.stderr)
        return 1

    payload = build_payload(entries, index_path.as_posix())
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(f"{json.dumps(payload, ensure_ascii=False, indent=2)}\n", encoding="utf-8")
    print(
        f"Wrote {output_path} "
        f"({payload['counts']['schools']} schools, {payload['counts']['generic']} generic)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
