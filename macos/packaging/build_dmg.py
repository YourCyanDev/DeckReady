#!/usr/bin/env python3
"""Build a branded DMG without relying on Finder or its asynchronous saves."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile

import dmgbuild
from ds_store import DSStore
from mac_alias import Alias


def run(*args):
    subprocess.run(args, check=True)


def verify(image, source_background):
    """Read the final, compressed image after two separate read-only mounts."""
    previous_store_hash = None
    with tempfile.TemporaryDirectory(prefix="deckready-dmg-check-") as directory:
        for attempt in (1, 2):
            mount = Path(directory) / ("reopen-%d" % attempt)
            mount.mkdir()
            run("hdiutil", "attach", str(image), "-readonly", "-nobrowse", "-noautoopen",
                "-mountpoint", str(mount))
            try:
                assert (mount / "DeckReady.app").is_dir(), "App missing from DMG"
                assert (mount / "Applications").is_symlink(), "Applications shortcut missing"
                background = mount / ".background.png"
                assert background.is_file(), "Background was not embedded in image"
                assert background.read_bytes() == source_background.read_bytes(), "Background differs from brand asset"
                store_path = mount / ".DS_Store"
                assert store_path.is_file(), "Finder layout is missing"
                with DSStore.open(str(store_path), "r") as store:
                    options = store["."]["icvp"]
                    assert options["backgroundType"] == 2, "Finder is not set to an image background"
                    alias = Alias.from_bytes(options["backgroundImageAlias"])
                    assert alias.target.filename == ".background.png", "Background alias targets another file"
                    assert alias.volume.name == "DeckReady", "Background alias points outside the DMG volume"
                    assert store["DeckReady.app"]["Iloc"] == (205, 305), "App icon position missing"
                    assert store["Applications"]["Iloc"] == (555, 305), "Applications icon position missing"
                current_hash = hashlib.sha256(store_path.read_bytes()).hexdigest()
                if previous_store_hash:
                    assert current_hash == previous_store_hash, "Saved Finder layout changed on remount"
                previous_store_hash = current_hash
            finally:
                run("hdiutil", "detach", str(mount))
    print("Verified embedded background, on-volume alias, icon positions and unchanged layout after two mounts.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--background", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    app, background, output = args.app.resolve(), args.background.resolve(), args.output.resolve()
    assert app.is_dir() and background.is_file()
    output.unlink(missing_ok=True)
    settings = {
        "format": "UDZO", "filesystem": "HFS+", "compression_level": 9,
        "files": [str(app)], "symlinks": {"Applications": "/Applications"},
        "background": str(background),
        "icon": str(app / "Contents/Resources/DeckReady.icns"),
        "icon_locations": {"DeckReady.app": (205, 305), "Applications": (555, 305)},
        "window_rect": ((160, 120), (760, 460)), "default_view": "icon-view",
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False,
        "show_pathbar": False, "show_sidebar": False, "show_icon_preview": False,
        "include_icon_view_settings": True, "arrange_by": None,
        "grid_spacing": 80, "icon_size": 128, "text_size": 15,
    }
    dmgbuild.build_dmg(str(output), "DeckReady", settings=settings)
    run("hdiutil", "verify", str(output))
    verify(output, background)


if __name__ == "__main__":
    main()
