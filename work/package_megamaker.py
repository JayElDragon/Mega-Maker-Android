"""Rebuild Mega Maker from the last installed APK with a new game.droid and the
Android GameMusicEmu extension (classes2.dex + libmmgme.so + options.ini)."""

import argparse
from copy import copy
from pathlib import Path
from shutil import copyfileobj
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

SIGNATURE_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC", "MANIFEST.MF")
EXTENSIONS = ["GameMusicEmu"]


def patch_options(text):
    lines = [line for line in text.splitlines()
             if not line.startswith(("YYNumExtensionClasses=", "YYExtensionClass"))]
    out, inserted = [], False
    for line in lines:
        out.append(line)
        if line.strip() == "[Android]" and not inserted:
            out.append(f"YYNumExtensionClasses={len(EXTENSIONS)}")
            out += [f"YYExtensionClass{i}={name}" for i, name in enumerate(EXTENSIONS)]
            inserted = True
    if not inserted:
        raise ValueError("options.ini has no [Android] section")
    return "\r\n".join(out) + "\r\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("data", type=Path)
    parser.add_argument("music", type=Path, help="work/music folder")
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--extra-asset", nargs=2, action="append", default=[],
                        metavar=("APK_PATH", "FILE"))
    args = parser.parse_args()

    replaced = {"assets/game.droid", "assets/options.ini", "classes2.dex", "AndroidManifest.xml"}
    libs = {f"lib/{abi.name}/libmmgme.so": abi / "libmmgme.so"
            for abi in (args.music / "lib").iterdir()}
    replaced |= set(libs) | {name for name, _ in args.extra_asset}

    with ZipFile(args.base) as base, ZipFile(args.output, "w") as apk:
        for entry in base.infolist():
            name = entry.filename
            if entry.is_dir() or name in replaced or (
                    name.startswith("META-INF/") and name.upper().endswith(SIGNATURE_SUFFIXES)):
                continue
            target = copy(entry)
            if name.startswith(("assets/Music/", "assets/ExampleLevels/")):
                # The Android runner lowercases included-file paths and turns
                # spaces into underscores.
                target.filename = name.lower().replace(" ", "_")
            with base.open(entry) as read, apk.open(target, "w") as write:
                copyfileobj(read, write)

        apk.write(args.manifest, "AndroidManifest.xml", ZIP_DEFLATED)
        options = patch_options(base.read("assets/options.ini").decode("utf-8"))
        apk.writestr("assets/options.ini", options, ZIP_DEFLATED)
        apk.write(args.music / "dex" / "classes.dex", "classes2.dex", ZIP_DEFLATED)
        for name, path in libs.items():
            apk.write(path, name, ZIP_STORED)
        apk.write(args.data, "assets/game.droid", ZIP_STORED)
        for name, path in args.extra_asset:
            apk.write(path, name, ZIP_DEFLATED)


if __name__ == "__main__":
    main()
