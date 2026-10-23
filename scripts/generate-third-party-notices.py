#!/usr/bin/env python3
"""Regenerate App/ThirdPartyNotices.txt from Config/Package.resolved and the SwiftPM checkouts.

Both apps bundle the output: the macOS app shows it under "Open-source licenses…", the iOS app under
Settings → About → Acknowledgements (issue #202). ThirdPartyNoticesTests fails when a pinned package
has no notice at its resolved revision, so run this whenever Config/Package.resolved changes:

    make ios-build            # resolves the pinned packages into .build/ios/SourcePackages
    python3 -I scripts/generate-third-party-notices.py [CHECKOUTS_DIR]

CHECKOUTS_DIR defaults to .build/ios/SourcePackages/checkouts. Each checkout must be at the pinned
revision; the script refuses to write otherwise.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULE = "=" * 72
HEADER = (
    "ListenToMe third-party software notices\n\n"
    "These notices accompany the dependency versions in Config/Package.resolved.\n"
    "Models downloaded on first use are distributed by their respective providers.\n"
)
NAMES = ("LICENSE", "LICENCE", "NOTICE", "COPYING")


def license_files(checkout: pathlib.Path) -> list[pathlib.Path]:
    top = sorted(p for p in checkout.iterdir() if p.is_file() and p.name.upper().startswith(NAMES))
    bundled = checkout / "ThirdPartyLicenses"
    extra = sorted(p for p in bundled.iterdir() if p.is_file()) if bundled.is_dir() else []
    return top + extra


def checkout_dir(checkouts: pathlib.Path, location: str) -> pathlib.Path:
    name = location.rstrip("/").split("/")[-1]
    return checkouts / (name[:-4] if name.endswith(".git") else name)


def main() -> int:
    checkouts = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".build/ios/SourcePackages/checkouts"
    pins = json.loads((ROOT / "Config/Package.resolved").read_text())["pins"]
    # Every piece is joined by one blank line plus the newline the previous piece ends with; license
    # files are copied verbatim, including their own leading and trailing blank lines.
    pieces = [HEADER]
    for pin in pins:
        state = pin["state"]
        checkout = checkout_dir(checkouts, pin["location"])
        head = subprocess.run(["git", "-C", str(checkout), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=False).stdout.strip()
        if head != state["revision"]:
            print(f"{pin['identity']}: {checkout} is at {head or 'nothing'}, expected {state['revision']}",
                  file=sys.stderr)
            return 1
        files = license_files(checkout)
        if not files:
            print(f"{pin['identity']}: no LICENSE/NOTICE file in {checkout}", file=sys.stderr)
            return 1
        version = state.get("version") or state.get("branch") or state["revision"][:12]
        pieces.append(f"{RULE}\n{pin['identity']} {version}\n{pin['location']}\nRevision: {state['revision']}\n")
        pieces += [f"--- {f.relative_to(checkout)} ---\n\n{f.read_text()}" for f in files]
    (ROOT / "App/ThirdPartyNotices.txt").write_text("\n\n".join(pieces))
    print(f"Wrote notices for {len(pins)} packages to App/ThirdPartyNotices.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
