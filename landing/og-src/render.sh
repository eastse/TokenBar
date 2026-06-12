#!/bin/sh
# Re-render the OG embed card from og.html → public/og-card.png (1200×630).
# Needs Chrome; fonts load from Google Fonts, so run online.
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
"$CHROME" --headless=new --screenshot=../public/og-card.png \
  --window-size=1200,630 --hide-scrollbars --virtual-time-budget=8000 \
  "file://$PWD/og.html"
sips -g pixelWidth -g pixelHeight ../public/og-card.png
