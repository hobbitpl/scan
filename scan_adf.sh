#!/bin/bash
set -o pipefail

clear

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
. "$DIR/local.config"

# -------------------------------------------------
# Timestamp
# -------------------------------------------------
var_year=$(date +%Y)
var_month=$(date +%m)
var_day=$(date +%d)
var_hour=$(date +%H)
var_min=$(date +%M)
var_sec=$(date +%S)

# -------------------------------------------------
# Input
# -------------------------------------------------
echo "Ile skanów? (ADF – zatrzyma się sam gdy pusty)"
read -r y

if [[ ! "$y" =~ ^[0-9]+$ ]] || [[ "$y" -le 0 ]]; then
  echo "❌ Nieprawidłowa liczba"
  exit 1
fi

x=0

# -------------------------------------------------
# Scan loop
# -------------------------------------------------
while [[ "$x" -lt "$y" ]]; do
  num=$(printf "%03d" "$x")
  var_filename="scan@${var_site}_D${var_year}_${var_month}_${var_day}_T${var_hour}_${var_min}_${var_sec}_${num}.jpg"
  outpath="$var_output_path/$var_filename"

  echo "Rozpoczynam skanowanie (strona $((x+1)))..."

  # --- scan ---
  if ! scanimage \
      --source "ADF Front" \
      --speed 4 \
      --resolution "$var_resolution" \
      --mode "$var_mode" \
      --format="$var_format" \
      > "$outpath" 2>/tmp/scan_err.log; then

    if grep -qi "Document feeder out of documents" /tmp/scan_err.log; then
      echo "ℹ️ ADF pusty – kończę skanowanie."
      rm -f "$outpath"
      break
    else
      echo "❌ Błąd skanowania:"
      cat /tmp/scan_err.log
      rm -f "$outpath"
      exit 1
    fi
  fi

  # --- sanity check ---
  if [[ ! -s "$outpath" ]]; then
    echo "ℹ️ Brak danych (ADF pusty?) – kończę."
    rm -f "$outpath"
    break
  fi

  # --- postprocess ---
  convert -rotate "$var_rotate" "$outpath" "$outpath"
  chmod 664 "$outpath"

  echo ""
  figlet "skan zapisano"
  echo "plik: $outpath"
  echo ""

  ((x++))
done

echo "🎉 Zakończono. Zeskanowano $x stron."
