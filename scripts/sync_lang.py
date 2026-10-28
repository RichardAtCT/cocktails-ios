#!/usr/bin/env python3
"""Bundles the website's translations of the phrases the app shows (Resources/Data/lang/<code>.json).

The site translates its pages with one phrase table (the [dt] phrases: English is the key; each
language has a human translation and a machine one, the human one winning). This reads that table
read-only from the live site's /admin/api/translation (the bearer token in
~/.config/decent/admin_api_token) and keeps only the phrases the app can show: every string
literal in Sources/, and every text value in the book dbs and the side JSON files the app bundles.
Each <code>.json is {english: translation}; English needs no file. Run by sync_data.sh."""
import json, os, re, sqlite3, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Resources", "Data")
OUT = os.path.join(DATA, "lang")
SERVER = os.environ.get("DECENT_SERVER", "https://decentespresso.com")
# the site's languages, less Polish (the site doesn't translate into it any more)
LANGS = ["de", "fr", "es", "kr", "ar", "zh-hans", "zh-hant"]


def fetch_all():
    tok = open(os.path.expanduser("~/.config/decent/admin_api_token")).read().strip()
    out, off = [], 0
    while True:
        # curl, not urllib: the python.org Python has no CA certificates by default
        r = subprocess.run(["curl", "-sf", "--max-time", "120", "-H", "Authorization: Bearer " + tok,
                            f"{SERVER}/admin/api/translation?limit=5000&offset={off}"], capture_output=True, check=True)
        j = json.loads(r.stdout)
        if not j.get("ok"):
            sys.exit(f"translation API: {j}")
        out += j["phrases"]
        off += j["returned"]
        if j["returned"] == 0 or off >= j["total"]:
            return out


def swift_literals():
    """every "..." in the Swift sources, unescaped; ones with \\( interpolation are skipped"""
    lit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
    # T("...") inside an interpolation ("\(T("Base spirit +")) …?") hides from the plain match
    tcall = re.compile(r'\bT\(\s*"((?:[^"\\\n]|\\.)*)"')
    out = set()
    for d, _, fs in os.walk(os.path.join(ROOT, "Sources")):
        for f in fs:
            if f.endswith(".swift"):
                src = open(os.path.join(d, f), encoding="utf-8").read()
                for m in list(lit.finditer(src)) + list(tcall.finditer(src)):
                    s = m.group(1)
                    if "\\(" in s:
                        continue
                    out.add(s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\"))
    return out


def data_strings():
    out = set()
    for f in os.listdir(DATA):
        p = os.path.join(DATA, f)
        if f.endswith(".db"):
            db = sqlite3.connect(p)
            for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'"):
                for row in db.execute(f'SELECT * FROM "{t}"'):
                    out.update(v for v in row if isinstance(v, str))
        elif f.endswith(".json"):
            def walk(v):
                if isinstance(v, str):
                    out.add(v)
                elif isinstance(v, list):
                    for x in v: walk(x)
                elif isinstance(v, dict):
                    for x in v.values(): walk(x)
            walk(json.load(open(p, encoding="utf-8")))
    # labels the app makes from short tags (category "fortified_wine" -> "Fortified wine",
    # spirit "gin" -> "Gin", keyword -> "Bitter"), as pdt_pretty_cat etc. do
    for v in list(out):
        if len(v) <= 40:
            w = v.replace("_", " ")
            out.update({w[:1].upper() + w[1:], w.title(), w.capitalize()})
    return out


def main():
    want = swift_literals() | data_strings()
    phrases = fetch_all()
    if os.environ.get("PHRASES_CACHE"):
        json.dump(phrases, open(os.environ["PHRASES_CACHE"], "w"))
    os.makedirs(OUT, exist_ok=True)
    for lang in LANGS:
        table = {}
        for p in phrases:
            en, tr = p.get("en", ""), p.get("translations", {})
            if en in want:
                v = tr.get(lang) or tr.get(lang + "m")
                if v and v != en:
                    table[en] = v
        json.dump(table, open(os.path.join(OUT, f"{lang}.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        print(f"{lang}: {len(table)} phrases")


if __name__ == "__main__":
    main()
