#!/usr/bin/env python3
"""Generate the GitHub Pages site (docs/index.html) from the experiment registry and the implementation guides.

Everything the page shows comes from the source: descriptors (Registry+*.swift), the Wallet credential catalog,
the promoted tools and the "How to implement" guides (ImplementationGuides/Guides+*.swift).
Run from the repository root:
    python3 scripts/generate-site.py
"""
import glob
import html
import importlib.util
import json
import os
import re
import textwrap

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GUIDES = os.path.join(ROOT, "AppleToolbox", "Shared", "ImplementationGuides")
OUT = os.path.join(ROOT, "docs", "index.html")
REPO = "https://github.com/JoKeks2023/apple-toolbox"

spec = importlib.util.spec_from_file_location("catalog", os.path.join(os.path.dirname(__file__), "generate-readme-catalog.py"))
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)

STRING = r'"((?:[^"\\]|\\.)*)"'


def string_array(block, label):
    """String literals of `label: [ … ]`, scanning past brackets inside the strings."""
    start = block.find(f"{label}: [")
    if start < 0:
        return []
    i, values = start + len(label) + 3, []
    while i < len(block):
        if block[i] == '"':
            m = re.compile(STRING).match(block, i)
            values.append(catalog.unescape(m.group(1)))
            i = m.end()
        elif block[i] == "]":
            break
        else:
            i += 1
    return values


def guides():
    found = {}
    for path in sorted(glob.glob(os.path.join(GUIDES, "Guides+*.swift"))):
        text = open(path, encoding="utf-8").read()
        for m in re.finditer(r'"([\w.-]+)": ImplementationGuide\(', text):
            end = text.find("\n        ),", m.end())
            block = text[m.end():end]
            snippet = re.search(r'snippet: #"""\n(.*?)\n[ \t]*"""#', block, re.S)
            platform = re.search(r"platform: \.(\w+)", block)
            rest = block[snippet.end():]
            plist = [dict(key=catalog.unescape(k), value=catalog.unescape(v))
                     for k, v in re.findall(r"\.init\(key: " + STRING + r", value: " + STRING + r"\)", rest)]
            found[m.group(1)] = dict(
                platform=platform.group(1) if platform else "iOS",
                snippet=textwrap.dedent(snippet.group(1)),
                plist=plist,
                entitlements=string_array(rest, "entitlements"),
                capabilities=string_array(rest, "capabilities"),
                notes=string_array(rest, "notes"),
            )
    return found


def data():
    names = dict(catalog.categories())
    guide_map = guides()
    items = []
    for e in catalog.experiments():
        items.append(dict(id=e["id"], name=e["name"], category=names[e["category"]], description=e["description"],
                          platforms=[catalog.PLATFORM_NAMES[p] for p in catalog.ALL_PLATFORMS if p in e["platforms"]],
                          guide=guide_map.get(e["id"])))
    return items, [title for _, title in catalog.categories()], catalog.tools()


def page(items, categories, tools):
    capabilities = len(re.findall(r"CapabilityDescriptor\(id:", open(os.path.join(
        catalog.SRC, "Shared/CapabilitySystem/CapabilityRegistry.swift"), encoding="utf-8").read()))
    guided = sum(1 for i in items if i["guide"])
    payload = json.dumps(dict(items=items, categories=categories), ensure_ascii=False).replace("</", "<\\/")
    tool_cards = "\n".join(
        f'<article class="tool"><h3>{html.escape(t["title"])}</h3><p>{html.escape(t["summary"])}</p>'
        f'<span class="from">from “{html.escape(t["origin"])}”</span></article>' for t in tools)
    return TEMPLATE.format(count=len(items), guided=guided, categories=len(categories), capabilities=capabilities,
                           tools=tool_cards, data=payload, repo=REPO)


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Apple Toolbox</title>
<meta name="description" content="A lab app for developers: {count} experiments that run real Apple APIs on your devices, each with the code, Info.plist keys and entitlements to build it yourself.">
<link rel="icon" href="assets/app-icon.png">
<meta property="og:title" content="Apple Toolbox">
<meta property="og:description" content="What can my Apple devices actually do — and how do I build it?">
<meta property="og:image" content="assets/app-icon.png">
<style>
:root {{
  --bg: #f5f5f7; --surface: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: #d2d2d7;
  --accent: #3d80ff; --accent2: #8040ff; --code-bg: #f2f2f5; --chip: #e8e8ed;
  --kw: #ad3da4; --str: #c41a16; --com: #707f8c; --type: #3900a0; --num: #1c00cf;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #000000; --surface: #1c1c1e; --text: #f5f5f7; --muted: #a1a1a6; --line: #38383a;
    --code-bg: #111113; --chip: #2c2c2e;
    --kw: #fc5fa3; --str: #fc6a5d; --com: #7f8c98; --type: #d0a8ff; --num: #d0bf69;
  }}
}}
* {{ box-sizing: border-box; }}
html {{ scroll-behavior: smooth; }}
body {{ margin: 0; background: var(--bg); color: var(--text); font: 17px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; -webkit-font-smoothing: antialiased; }}
a {{ color: var(--accent); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
.wrap {{ max-width: 1080px; margin: 0 auto; padding: 0 20px; }}
nav {{ position: sticky; top: 0; z-index: 10; backdrop-filter: saturate(180%) blur(20px); -webkit-backdrop-filter: saturate(180%) blur(20px); background: color-mix(in srgb, var(--bg) 72%, transparent); border-bottom: 1px solid var(--line); }}
nav .wrap {{ display: flex; align-items: center; gap: 20px; height: 52px; font-size: 14px; }}
nav .brand {{ display: flex; align-items: center; gap: 8px; font-weight: 600; color: var(--text); margin-right: auto; }}
nav .brand img {{ width: 24px; height: 24px; }}
nav a {{ color: var(--text); opacity: .8; }}
header.wrap {{ text-align: center; padding: 88px 20px 56px; }}
header img {{ width: 148px; height: 148px; filter: drop-shadow(0 18px 36px rgba(80, 60, 255, .28)); }}
h1 {{ font-size: clamp(40px, 7vw, 72px); line-height: 1.05; letter-spacing: -.02em; margin: 24px 0 12px; }}
.lead {{ font-size: clamp(19px, 2.6vw, 25px); color: var(--muted); max-width: 760px; margin: 0 auto; }}
.gradient {{ background: linear-gradient(90deg, var(--accent), var(--accent2)); -webkit-background-clip: text; background-clip: text; color: transparent; }}
.cta {{ display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; margin-top: 32px; }}
.btn {{ display: inline-block; padding: 12px 22px; border-radius: 980px; font-weight: 500; font-size: 16px; }}
.btn.primary {{ background: var(--accent); color: #fff; }}
.btn.secondary {{ border: 1px solid var(--accent); }}
.btn:hover {{ text-decoration: none; filter: brightness(1.08); }}
.stats {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin: 8px 0 72px; }}
.stat {{ background: var(--surface); border-radius: 18px; padding: 20px; text-align: center; }}
.stat b {{ display: block; font-size: 34px; letter-spacing: -.02em; }}
.stat span {{ color: var(--muted); font-size: 14px; }}
section.wrap {{ padding: 32px 20px 64px; }}
h2 {{ font-size: clamp(28px, 4vw, 40px); letter-spacing: -.015em; margin: 0 0 8px; }}
.sub {{ color: var(--muted); margin: 0 0 28px; max-width: 720px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; }}
.feature, .tool {{ background: var(--surface); border-radius: 18px; padding: 24px; }}
.feature h3, .tool h3 {{ margin: 0 0 6px; font-size: 19px; }}
.feature p, .tool p {{ margin: 0; color: var(--muted); font-size: 15px; }}
.tool .from {{ display: block; margin-top: 10px; font-size: 13px; color: var(--muted); }}
.filters {{ display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; position: sticky; top: 52px; background: var(--bg); padding: 10px 0; z-index: 5; }}
.filters input, .filters select {{ font: inherit; font-size: 15px; color: var(--text); background: var(--surface); border: 1px solid var(--line); border-radius: 12px; padding: 10px 14px; }}
.filters input {{ flex: 1 1 260px; }}
.count {{ color: var(--muted); font-size: 14px; margin: 0 0 12px; }}
.exp {{ background: var(--surface); border-radius: 16px; margin-bottom: 10px; overflow: hidden; }}
.exp summary {{ list-style: none; cursor: pointer; padding: 16px 20px; display: grid; grid-template-columns: 1fr auto; gap: 4px 16px; }}
.exp summary::-webkit-details-marker {{ display: none; }}
.exp summary h3 {{ margin: 0; font-size: 17px; }}
.exp summary p {{ margin: 0; grid-column: 1 / -1; color: var(--muted); font-size: 15px; }}
.meta {{ display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; align-items: start; }}
.chip {{ background: var(--chip); border-radius: 980px; padding: 2px 10px; font-size: 12px; color: var(--muted); white-space: nowrap; }}
.chip.cat {{ color: var(--accent); }}
.body {{ padding: 0 20px 20px; border-top: 1px solid var(--line); }}
.body h4 {{ margin: 18px 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); display: flex; justify-content: space-between; align-items: center; }}
.copy {{ font: inherit; font-size: 12px; text-transform: none; letter-spacing: 0; color: var(--accent); background: none; border: 1px solid var(--line); border-radius: 8px; padding: 3px 10px; cursor: pointer; }}
pre {{ margin: 0; background: var(--code-bg); border-radius: 12px; padding: 14px 16px; overflow-x: auto; font: 13px/1.55 ui-monospace, "SF Mono", Menlo, monospace; }}
.kw {{ color: var(--kw); font-weight: 600; }} .str {{ color: var(--str); }} .com {{ color: var(--com); font-style: italic; }} .ty {{ color: var(--type); }} .num {{ color: var(--num); }}
.body ul {{ margin: 0; padding-left: 20px; color: var(--text); font-size: 15px; }}
.body li {{ margin: 4px 0; }}
.none {{ color: var(--muted); font-size: 15px; margin: 16px 0 0; }}
.steps {{ counter-reset: step; display: grid; gap: 12px; padding: 0; list-style: none; }}
.steps li {{ background: var(--surface); border-radius: 16px; padding: 18px 20px 18px 60px; position: relative; }}
.steps li::before {{ counter-increment: step; content: counter(step); position: absolute; left: 20px; top: 18px; width: 26px; height: 26px; border-radius: 50%; background: var(--accent); color: #fff; font-size: 14px; font-weight: 600; display: grid; place-items: center; }}
.steps pre {{ margin-top: 10px; }}
footer {{ border-top: 1px solid var(--line); padding: 28px 0 48px; color: var(--muted); font-size: 13px; }}
@media (max-width: 720px) {{
  .stats {{ grid-template-columns: repeat(2, 1fr); }}
  nav .links {{ display: none; }}
  .exp summary {{ grid-template-columns: 1fr; }}
  .meta {{ justify-content: flex-start; }}
}}
</style>
</head>
<body>
<nav><div class="wrap">
  <a class="brand" href="#"><img src="assets/app-icon.png" alt="">Apple Toolbox</a>
  <span class="links"><a href="#features">Features</a> · <a href="#experiments">Experiments</a> · <a href="#start">Get started</a></span>
  <a href="{repo}">GitHub</a>
</div></nav>

<header class="wrap">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/app-icon-dark.png">
    <img src="assets/app-icon.png" alt="Apple Toolbox app icon">
  </picture>
  <h1>What can your devices <span class="gradient">actually do?</span></h1>
  <p class="lead">A lab app for developers. {count} experiments run real Apple APIs on your iPhone, iPad, Mac, Apple Watch and Apple TV — and show you the code to build each one yourself.</p>
  <div class="cta">
    <a class="btn primary" href="#experiments">Browse experiments</a>
    <a class="btn secondary" href="{repo}">View on GitHub</a>
  </div>
</header>

<div class="wrap stats">
  <div class="stat"><b>{count}</b><span>experiments</span></div>
  <div class="stat"><b>{guided}</b><span>implementation guides</span></div>
  <div class="stat"><b>{categories}</b><span>categories</span></div>
  <div class="stat"><b>{capabilities}</b><span>capabilities explained</span></div>
</div>

<section id="features" class="wrap">
  <h2>Try it, then build it.</h2>
  <p class="sub">Every experiment calls the real public API on the device in your hand. Nothing is simulated, and when something doesn't work, the app tells you exactly why.</p>
  <div class="grid">
    <article class="feature"><h3>How to implement</h3><p>Minimal Swift code for the core API, the Info.plist keys, entitlements and capabilities — ready to copy. Every snippet typechecks against the SDK.</p></article>
    <article class="feature"><h3>“Why doesn't this work?”</h3><p>Missing hardware, a declined permission, an entitlement Apple has to approve or a platform without the framework — each reason explained with the next step.</p></article>
    <article class="feature"><h3>Pre-run checks</h3><p>Platform, OS, hardware, permissions, entitlements and Apple programs are checked before you start, without triggering a permission prompt.</p></article>
    <article class="feature"><h3>Entitlement Explorer</h3><p>{capabilities} Apple capabilities with their entitlement keys, how to get them, and whether this build is provisioned for them.</p></article>
    <article class="feature"><h3>Device Scanner</h3><p>What your device exposes through public APIs: chip, sensors, cameras, radios, display, Apple Intelligence and more.</p></article>
    <article class="feature"><h3>Every Apple platform</h3><p>One Swift 6 codebase for iOS, iPadOS, macOS, watchOS and tvOS, with widgets, a Live Activity, controls, complications and four app extensions.</p></article>
  </div>
</section>

<section id="tools" class="wrap">
  <h2>Tools, not just demos.</h2>
  <p class="sub">Mature experiments grew into utilities you can keep using.</p>
  <div class="grid">
{tools}
  </div>
</section>

<section id="experiments" class="wrap">
  <h2>Experiments</h2>
  <p class="sub">Open one to see how to build it in your own app.</p>
  <div class="filters">
    <input id="q" type="search" placeholder="Search experiments, frameworks, entitlements…" aria-label="Search">
    <select id="cat" aria-label="Category"><option value="">All categories</option></select>
    <select id="plat" aria-label="Platform">
      <option value="">All platforms</option><option>iPhone</option><option>iPad</option><option>Mac</option><option>Watch</option><option>TV</option>
    </select>
  </div>
  <p class="count" id="count"></p>
  <div id="list"></div>
</section>

<section id="start" class="wrap">
  <h2>Get started</h2>
  <p class="sub">Xcode 26 or newer. Deployment targets: iOS / iPadOS 26.5, macOS 26.5, tvOS 26.0, watchOS 11.0.</p>
  <ol class="steps">
    <li>Clone the repository.<pre>git clone {repo}.git</pre></li>
    <li>Set your signing team and a bundle ID prefix you own — once, for every target.<pre>cp Config/Local.xcconfig.example Config/Local.xcconfig</pre></li>
    <li>Open <code>AppleToolbox.xcodeproj</code>, pick a scheme and run it on a real device. Sensors, radios, the Secure Enclave, NFC and UWB need hardware; the Simulator shows the rest.</li>
  </ol>
</section>

<footer><div class="wrap">
  MIT License · <a href="{repo}">Source on GitHub</a> · Generated from the source by <code>scripts/generate-site.py</code>.<br>
  Apple, iPhone, iPad, Mac, Apple Watch, Apple TV and the frameworks named here are trademarks of Apple Inc. This project is not affiliated with or endorsed by Apple.
</div></footer>

<script type="application/json" id="data">{data}</script>
<script>
const {{ items, categories }} = JSON.parse(document.getElementById("data").textContent);
const $ = (id) => document.getElementById(id);
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({{ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }})[c]);
for (const c of categories) $("cat").add(new Option(c, c));

const KEYWORDS = new Set("actor async await break case catch class continue default defer do else enum extension fallthrough false final for func guard if import in init inout internal is let nil nonisolated override private public return self Self some static struct super switch throw throws true try var weak where while any convenience lazy mutating open required rethrows get set willSet didSet".split(" "));
function highlight(code) {{
  const token = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/)|("(?:[^"\\\n]|\\.)*")|(@\w+|#\w+)|\b(\d[\d_.]*)\b|\b([A-Za-z_]\w*)\b/g;
  let out = "", last = 0, m;
  while ((m = token.exec(code))) {{
    out += esc(code.slice(last, m.index));
    const [t] = m;
    if (m[1]) out += `<span class="com">${{esc(t)}}</span>`;
    else if (m[2]) out += `<span class="str">${{esc(t)}}</span>`;
    else if (m[3]) out += `<span class="kw">${{esc(t)}}</span>`;
    else if (m[4]) out += `<span class="num">${{esc(t)}}</span>`;
    else if (KEYWORDS.has(t)) out += `<span class="kw">${{t}}</span>`;
    else if (/^[A-Z]/.test(t)) out += `<span class="ty">${{t}}</span>`;
    else out += t;
    last = token.lastIndex;
  }}
  return out + esc(code.slice(last));
}}

function plistXML(entries) {{
  return entries.map((e) => `<key>${{e.key}}</key>\n${{e.value.startsWith("<") ? e.value : `<string>${{e.value}}</string>`}}`).join("\n");
}}

function block(title, text, highlighted) {{
  return `<h4>${{title}}<button class="copy" data-copy="${{esc(text)}}">Copy</button></h4><pre>${{highlighted ? highlight(text) : esc(text)}}</pre>`;
}}

function detail(item) {{
  const g = item.guide;
  if (!g) return `<p class="none">Available through an Apple program only: the app shows what it needs and whether this device is eligible.</p>`;
  let out = block(`Swift · ${{g.platform}}`, g.snippet, true);
  if (g.plist.length) out += block("Info.plist", plistXML(g.plist), false);
  if (g.entitlements.length) out += block("Entitlements", g.entitlements.join("\n"), false);
  if (g.capabilities.length) out += `<h4>Signing &amp; Capabilities</h4><ul>${{g.capabilities.map((c) => `<li>${{esc(c)}}</li>`).join("")}}</ul>`;
  if (g.notes.length) out += `<h4>Good to know</h4><ul>${{g.notes.map((n) => `<li>${{esc(n)}}</li>`).join("")}}</ul>`;
  return out;
}}

function haystack(item) {{
  const g = item.guide || {{}};
  return [item.name, item.category, item.description, g.snippet || "", ...(g.entitlements || []), ...(g.capabilities || []),
          ...(g.plist || []).map((p) => p.key)].join(" ").toLowerCase();
}}
const index = items.map(haystack);

function render() {{
  const q = $("q").value.trim().toLowerCase(), cat = $("cat").value, plat = $("plat").value;
  const shown = items.filter((item, i) => (!cat || item.category === cat) && (!plat || item.platforms.includes(plat)) && (!q || q.split(/\s+/).every((w) => index[i].includes(w))));
  $("count").textContent = `${{shown.length}} of ${{items.length}} experiments`;
  $("list").innerHTML = shown.map((item) => `
    <details class="exp" id="${{item.id}}">
      <summary>
        <h3>${{esc(item.name)}}</h3>
        <div class="meta"><span class="chip cat">${{esc(item.category)}}</span>${{item.platforms.map((p) => `<span class="chip">${{p}}</span>`).join("")}}</div>
        <p>${{esc(item.description)}}</p>
      </summary>
      <div class="body">${{detail(item)}}</div>
    </details>`).join("");
}}

for (const id of ["q", "cat", "plat"]) $(id).addEventListener("input", render);
document.addEventListener("click", async (event) => {{
  const button = event.target.closest(".copy");
  if (!button) return;
  try {{ await navigator.clipboard.writeText(button.dataset.copy); button.textContent = "Copied"; }}
  catch {{ button.textContent = "Select and copy"; }}
  setTimeout(() => (button.textContent = "Copy"), 1600);
}});
render();
if (location.hash && document.getElementById(location.hash.slice(1))?.tagName === "DETAILS") document.getElementById(location.hash.slice(1)).open = true;
</script>
</body>
</html>
"""

if __name__ == "__main__":
    items, categories, tools = data()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page(items, categories, tools))
    open(os.path.join(ROOT, "docs", ".nojekyll"), "w").close()
    print(f"docs/index.html: {len(items)} experiments, {sum(1 for i in items if i['guide'])} with guides, {len(tools)} tools")
