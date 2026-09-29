#!/usr/bin/env python3
"""Regenerate the tools table, the experiment catalog and the experiment count in README.md.

Reads the experiment descriptors (AppleToolbox/Shared/ExperimentRegistry/Registry+*.swift),
the advanced Wallet credential catalog and the promoted tools, then rewrites the blocks
between the <!-- …:start --> / <!-- …:end --> markers. Run from the repository root:
    python3 scripts/generate-readme-catalog.py
"""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "AppleToolbox")
README = os.path.join(ROOT, "README.md")
STRING = r'"((?:[^"\\]|\\.)*)"'
PLATFORM_NAMES = {"iOS": "iPhone", "iPadOS": "iPad", "macOS": "Mac", "watchOS": "Watch", "tvOS": "TV"}
ALL_PLATFORMS = list(PLATFORM_NAMES)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def unescape(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def platforms(expression):
    if "allCases" in expression:
        return ALL_PLATFORMS
    return re.findall(r"\.(iOS|iPadOS|macOS|watchOS|tvOS)\b", expression)


def categories():
    models = read(os.path.join(SRC, "Shared/Models/ExperimentModels.swift"))
    body = models[models.index("enum ExperimentCategory"):]
    return re.findall(r'case (\w+) = "([^"]+)"', body[:body.index("var id")])


def experiments():
    found = []
    for path in sorted(glob.glob(os.path.join(SRC, "Shared/ExperimentRegistry/Registry+*.swift"))):
        text = read(path)
        for match in re.finditer(r'ExperimentDescriptor\(id: "([^"]+)", name: ' + STRING + r', category: \.(\w+)', text):
            rest = text[match.end():]
            description = re.search(r"description: " + STRING, rest).group(1)
            supported = re.search(r"supportedPlatforms: (\[[^\]]*\]|SupportedPlatform\.allCases)", rest).group(1)
            found.append(dict(id=match.group(1), name=unescape(match.group(2)), category=match.group(3),
                              description=unescape(description), platforms=platforms(supported)))
    wallet = read(os.path.join(SRC, "Shared/Services/AdvancedWalletServices.swift"))
    for match in re.finditer(r'AdvancedCredential\(id: "([^"]+)", name: ' + STRING, wallet):
        summary = re.search(r"summary: " + STRING, wallet[match.end():]).group(1)
        found.append(dict(id=match.group(1), name=unescape(match.group(2)), category="wallet",
                          description=unescape(summary) + " Shown with its Apple program requirements.", platforms=["iOS"]))
    return found


def tools():
    text = read(os.path.join(SRC, "Shared/Models/ToolboxTools.swift"))
    pattern = (r'ToolboxTool\(id: "([^"]+)", title: ' + STRING + r', symbolName: "[^"]+", promotedFrom: ' + STRING
               + r',\s*summary: ' + STRING)
    return [dict(id=m.group(1), title=m.group(2), origin=m.group(3), summary=unescape(m.group(4)))
            for m in re.finditer(pattern, text)]


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def catalog_markdown(items):
    names = dict(categories())
    blocks = []
    for key, title in categories():
        rows = [e for e in items if e["category"] == key]
        if not rows:
            continue
        lines = [f"<details>\n<summary><b>{title}</b> · {len(rows)} experiment{'s' if len(rows) != 1 else ''}</summary>\n",
                 "| Experiment | What it does | Runs on |", "| --- | --- | --- |"]
        for e in rows:
            runs = " · ".join(PLATFORM_NAMES[p] for p in ALL_PLATFORMS if p in e["platforms"])
            lines.append(f"| **{cell(e['name'])}** | {cell(e['description'])} | {runs} |")
        lines.append("\n</details>")
        blocks.append("\n".join(lines))
    assert set(e["category"] for e in items) <= set(names), "unknown category"
    return "\n\n".join(blocks)


def tools_markdown(entries, items):
    by_id = {e["id"]: e for e in items}
    lines = ["| Tool | Grew out of | What it does |", "| --- | --- | --- |"]
    for tool in entries:
        assert tool["id"] in by_id, f"tool {tool['id']} has no experiment"
        lines.append(f"| **{cell(tool['title'])}** | “{cell(tool['origin'])}” | {cell(tool['summary'])} |")
    return "\n".join(lines)


def replace(readme, marker, content):
    start, end = f"<!-- {marker}:start -->", f"<!-- {marker}:end -->"
    assert start in readme and end in readme, f"missing {marker} markers"
    head, rest = readme.split(start, 1)
    _, tail = rest.split(end, 1)
    return f"{head}{start}\n{content}\n{end}{tail}"


if __name__ == "__main__":
    items = experiments()
    readme = read(README)
    readme = replace(readme, "tools", tools_markdown(tools(), items))
    readme = replace(readme, "catalog", catalog_markdown(items))
    readme = re.sub(r"(img\.shields\.io/badge/experiments-)\d+", rf"\g<1>{len(items)}", readme)
    readme = re.sub(r"\*\*\d+ experiments\*\*", f"**{len(items)} experiments**", readme)
    capabilities = len(re.findall(r"CapabilityDescriptor\(id:", read(os.path.join(SRC, "Shared/CapabilitySystem/CapabilityRegistry.swift"))))
    readme = re.sub(r"\d+ Apple capabilities", f"{capabilities} Apple capabilities", readme)
    with open(README, "w", encoding="utf-8") as f:
        f.write(readme)
    print(f"{len(items)} experiments in {len({e['category'] for e in items})} categories, {len(tools())} tools")
