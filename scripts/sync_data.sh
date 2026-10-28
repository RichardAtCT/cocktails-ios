#!/bin/bash
# Copies the site's data into the app bundle (Resources/Data, a folder reference):
# the per-book sqlite dbs + side JSON from /d/admin, and every AVIF picture from
# /d/cocktails/img (~4.5 MB in all), so the app browses fully offline.
# Re-run after the site's data or pictures change, then rebuild.
set -euo pipefail
D=${D:-/d}
OUT="$(cd "$(dirname "$0")/.." && pwd)/Resources/Data"
rm -rf "$OUT"; mkdir -p "$OUT/img"
for f in pdt.db deathco.db pdt_similar_taste.json deathco_similar_taste.json ingredient_substitutes.json; do
	cp "$D/admin/$f" "$OUT/"
done
cd "$D/cocktails/img"
for dir in pdt deathco ingredients glasses spirits spirits/pair; do
	mkdir -p "$OUT/img/$dir"
	cp $dir/*.avif "$OUT/img/$dir/" 2>/dev/null || true
done
cp hero.avif hero-*.avif "$OUT/img/"
# the scale maker's Tare step: a shaker tin on the Half Decent Scale
mkdir -p "$OUT/img/maker"
cp maker/shaker-scale.jpg "$OUT/img/maker/"
# the scale picture on the recipe page's "Make this cocktail" button
cp "$D/img/small/DE-SCALETHIN_V2-75870-add-06_220x142.avif" "$OUT/img/scale-cta.avif"
# the site's translations of every phrase the app shows (live /admin/api/translation, read-only)
python3 "$(dirname "$0")/sync_lang.py"
du -sh "$OUT"
