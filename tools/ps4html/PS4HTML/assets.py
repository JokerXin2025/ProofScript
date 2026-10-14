"""Installed package assets; no checkout or home-directory installation required."""

from importlib.resources import files
from pathlib import Path


def publish_assets(destination: Path) -> None:
    def copy_tree(source, target):
        target.mkdir(parents=True, exist_ok=True)
        for child in source.iterdir():
            output = target / child.name
            if child.is_dir():
                copy_tree(child, output)
            else:
                output.write_bytes(child.read_bytes())

    copy_tree(files("PS4HTML").joinpath("assets"), destination)
