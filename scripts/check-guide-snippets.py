#!/usr/bin/env python3
"""Typecheck every "How to implement" snippet against the real SDK (Swift 6).

Reads AppleToolbox/Shared/ImplementationGuides/Guides+*.swift, writes each snippet to its own file and runs
`swiftc -typecheck` for the guide's platform (device SDKs, so frameworks such as Core NFC are present).
Run from the repository root:
    python3 scripts/check-guide-snippets.py            # every snippet
    python3 scripts/check-guide-snippets.py cryptokit  # only these experiment ids
"""
import glob
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GUIDES = os.path.join(ROOT, "AppleToolbox", "Shared", "ImplementationGuides")
TARGETS = {
    "iOS": ("iphoneos", "arm64-apple-ios26.5"),
    "macOS": ("macosx", "arm64-apple-macos26.5"),
    "tvOS": ("appletvos", "arm64-apple-tvos26.0"),
    "watchOS": ("watchos", "arm64_32-apple-watchos11.0"),
}
PATTERN = re.compile(r'"([\w.-]+)": ImplementationGuide\(\s*(?:platform: \.(\w+),\s*)?snippet: #"""\n(.*?)\n[ \t]*"""#', re.S)


def snippets():
    for path in sorted(glob.glob(os.path.join(GUIDES, "Guides+*.swift"))):
        for match in PATTERN.finditer(open(path, encoding="utf-8").read()):
            yield match.group(1), match.group(2) or "iOS", textwrap.dedent(match.group(3)), os.path.basename(path)


def sdk_path(sdk):
    return subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()


def check(item, folder):
    experiment, platform, code, source = item
    sdk, target = TARGETS[platform]
    file = os.path.join(folder, f"{experiment}.swift")
    with open(file, "w", encoding="utf-8") as f:
        f.write(code + "\n")
    result = subprocess.run(["xcrun", "--sdk", sdk, "swiftc", "-typecheck", "-swift-version", "6", "-parse-as-library",
                             "-target", target, "-sdk", sdk_path(sdk), file], capture_output=True, text=True)
    errors = [line.replace(file, f"{source} › {experiment}") for line in result.stderr.splitlines() if ": error:" in line]
    return experiment, platform, result.returncode == 0, errors


if __name__ == "__main__":
    wanted = set(sys.argv[1:])
    items = [item for item in snippets() if not wanted or item[0] in wanted]
    with tempfile.TemporaryDirectory() as folder, ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda item: check(item, folder), items))
    failed = [r for r in results if not r[2]]
    for experiment, platform, _, errors in failed:
        print(f"FAIL {experiment} ({platform})")
        print("\n".join(f"  {e}" for e in errors[:6]))
    print(f"{len(results) - len(failed)}/{len(results)} snippets typecheck")
    sys.exit(1 if failed else 0)
