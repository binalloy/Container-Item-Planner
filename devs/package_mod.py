#!/usr/bin/env python3
"""Build a Factorio mod ZIP and copy it to the Factorio mods directory."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DESTINATION = Path.home() / "Programs" / "factorio" / "mods"
REQUIRED_FILES = ("info.json", "data.lua", "control.lua", "gui.lua", "planner.lua")


def package(destination: Path) -> Path:
    info_path = ROOT / "info.json"
    with info_path.open(encoding="utf-8") as stream:
        info = json.load(stream)

    name = info.get("name")
    version = info.get("version")
    if not name or not version:
        raise ValueError("info.json must define non-empty 'name' and 'version' fields")

    files = [ROOT / filename for filename in REQUIRED_FILES]
    files.extend(sorted((ROOT / "locale").rglob("*")))
    files = [path for path in files if path.is_file()]
    if not all((ROOT / filename).is_file() for filename in REQUIRED_FILES):
        raise FileNotFoundError("Expected info.json, data.lua, and control.lua in the mod root")

    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f"{name}_{version}.zip"
    fd, temporary_name = tempfile.mkstemp(prefix=f".{name}_", suffix=".zip", dir=destination)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(files):
                archive_path = Path(f"{name}_{version}") / path.relative_to(ROOT)
                bundle.write(path, archive_path.as_posix())
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_DESTINATION,
        help=f"destination mods directory (default: {DEFAULT_DESTINATION})",
    )
    args = parser.parse_args()
    print(package(args.output.expanduser()).resolve())


if __name__ == "__main__":
    main()
