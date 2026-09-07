from __future__ import annotations

import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGES = ROOT / "docs"
GAMES = ROOT / "games"


def yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def read_title_and_body(readme: Path) -> tuple[str, str]:
    text = readme.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ValueError(f"README must start with an H1 title: {readme}")

    title = lines[0][2:].strip()
    body_lines = lines[1:]
    while body_lines and not body_lines[0].strip():
        body_lines.pop(0)
    return title, "\n".join(body_lines).rstrip() + "\n"


def main() -> None:
    data_directory = PAGES / "_data"
    data_directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(GAMES / "catalog.yml", data_directory / "catalog.yml")

    pages_games = PAGES / "games"
    pages_games.mkdir(parents=True, exist_ok=True)
    source_slugs = {path.name for path in GAMES.iterdir() if path.is_dir()}
    for stale_directory in pages_games.iterdir():
        if stale_directory.is_dir() and stale_directory.name not in source_slugs:
            shutil.rmtree(stale_directory)

    for game_directory in sorted(GAMES.iterdir()):
        if not game_directory.is_dir():
            continue
        readme = game_directory / "README.md"
        if not readme.exists():
            continue

        title, body = read_title_and_body(readme)
        target = pages_games / game_directory.name
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True, exist_ok=True)
        front_matter = (
            "---\n"
            "layout: game\n"
            f"title: {yaml_string(title)}\n"
            f"game_id: {yaml_string(game_directory.name)}\n"
            f"permalink: /games/{game_directory.name}/\n"
            "---\n\n"
        )
        (target / "index.md").write_text(front_matter + body, encoding="utf-8")

        patch_directory = game_directory / "patch"
        if patch_directory.exists():
            shutil.copytree(patch_directory, target / "patch")

    print(f"Synchronized GitHub Pages content in {PAGES}")


if __name__ == "__main__":
    main()
