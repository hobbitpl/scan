#!/bin/bash
set -euo pipefail

# -------------------------------------------------
# Init
# -------------------------------------------------
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
. "$DIR/local.config"

# Walidacja
: "${var_source:?❌ Brak var_source (np. \"ADF Front\")}"
: "${var_resolution:?❌ Brak var_resolution}"
: "${var_mode:?❌ Brak var_mode}"
: "${var_format:?❌ Brak var_format}"
: "${var_output_path:?❌ Brak var_output_path}"
: "${var_site:?❌ Brak var_site}"

timestamp=$(date +"%Y_%m_%d_T%H_%M_%S")

# -------------------------------------------------
# Input
# -------------------------------------------------
echo "Ile stron chcesz zeskanować? (ADF – avision)"
read -r pages

if [[ ! "$pages" =~ ^[0-9]+$ ]] || [[ "$pages" -le 0 ]]; then
  echo "❌ Nieprawidłowa liczba stron"
  exit 1
fi

# -------------------------------------------------
# Scan loop (avision – stdout)
# -------------------------------------------------
echo "⏳ Skanuję $pages stron (ADF Front, stdout)..."

for ((i=1; i<=pages; i++)); do
  num=$(printf "%03d" "$i")
  outfile="scan@${var_site}_${timestamp}_${num}.${var_format}"
  outpath="$var_output_path/$outfile"

  echo "→ Strona $i → $outfile"

  scanimage \
    --source="$var_source" \
    --speed 4 \
    --resolution="$var_resolution" \
    --mode="$var_mode" \
    --format="$var_format" \
    > "$outpath"

  chmod 664 "$outpath"
done

echo "🎉 Gotowe – zeskanowano $pages stron."
