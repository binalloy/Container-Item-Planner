#!/usr/bin/env python3
"""Create the 144x144 Mod Portal thumbnail from Factorio's item icons."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


MOD_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FACTORIO_DIR = Path.home() / "Programs" / "factorio"
ICON_SIZE = 64
THUMBNAIL_SIZE = 144
CHEST_SIZE = 96


def load_icon(path: Path) -> Image.Image:
    with Image.open(path) as source:
        if source.width < ICON_SIZE or source.height < ICON_SIZE:
            raise ValueError(f"Icon image is smaller than {ICON_SIZE}x{ICON_SIZE}: {path}")
        return source.convert("RGBA").crop((0, 0, ICON_SIZE, ICON_SIZE))


def create_thumbnail(factorio_dir: Path, output: Path) -> Path:
    icons_dir = factorio_dir / "data" / "base" / "graphics" / "icons"
    blueprint = load_icon(icons_dir / "blueprint.png")
    chest = load_icon(icons_dir / "iron-chest.png")

    resampling = Image.Resampling.LANCZOS
    blueprint = blueprint.resize((THUMBNAIL_SIZE, THUMBNAIL_SIZE), resampling)
    chest = chest.resize((CHEST_SIZE, CHEST_SIZE), resampling)

    thumbnail = blueprint.copy()
    offset = ((THUMBNAIL_SIZE - CHEST_SIZE) // 2,) * 2
    thumbnail.alpha_composite(chest, dest=offset)

    output.parent.mkdir(parents=True, exist_ok=True)
    thumbnail.save(output, format="PNG")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--factorio-dir",
        type=Path,
        default=DEFAULT_FACTORIO_DIR,
        help=f"Factorio install directory (default: {DEFAULT_FACTORIO_DIR})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=MOD_ROOT / "thumbnail.png",
        help=f"output PNG path (default: {MOD_ROOT / 'thumbnail.png'})",
    )
    args = parser.parse_args()

    try:
        output = create_thumbnail(args.factorio_dir.expanduser(), args.output.expanduser())
    except (FileNotFoundError, OSError, ValueError) as error:
        parser.error(str(error))
    print(output.resolve())


if __name__ == "__main__":
    main()
