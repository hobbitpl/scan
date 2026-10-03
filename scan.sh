#!/bin/bash
# Skanowanie z CLI (SANE). Każdy skan zapisywany jest jako oryginał
# oraz jako wersja zoptymalizowana (JPEG, mniejszy rozmiar).
clear
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
. "$DIR/local.config"

# wartości domyślne, jeśli brak w local.config
: "${var_resolution:=300}" "${var_mode:=Gray}" "${var_format:=tiff}" "${var_rotate:=0}" "${var_site:=$HOSTNAME}"
: "${var_opt_quality:=80}"   # jakość JPEG wersji zoptymalizowanej
: "${var_opt_max_dpi:=300}"  # wersja zoptymalizowana nie przekracza tej rozdzielczości
: "${var_opt_enhance:=1}"    # 1 = automatyczna korekcja bieli/czerni w wersji zoptymalizowanej
: "${var_opt_gamma:=0.8}"    # < 1 przyciemnia półtony (pismo, ołówek), 1 = bez zmian

case "$var_format" in
    jpeg) ext=jpg ;;
    *)    ext=$var_format ;;
esac

stamp=$(date +%Y_%m_%d_T%H_%M_%S)
x=0
total_orig=0
total_opt=0
in_progress=""
errlog=$(mktemp)

# kolory
B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; RED=$'\e[31m'

human() { numfmt --to=iec-i --suffix=B --format=%.1f "$1"; }

show_menu() {
    local header
    header=$(printf "SKANER  @%s   strona %03d   %s" "$var_site" "$((x + 1))" "$(date +%H:%M)")
    printf '\n %s╭────────────────────────────────────────────────╮%s\n' "$C" "$R"
    printf ' %s│%s  %s%-46s%s%s│%s\n' "$C" "$R" "$B" "$header" "$R" "$C" "$R"
    printf ' %s╰────────────────────────────────────────────────╯%s\n' "$C" "$R"
    printf '   %s[Enter]%s  Standard       %s%s · %s dpi%s\n' "$Y" "$R" "$D" "$var_mode" "$var_resolution" "$R"
    printf '   %s[1]%s      Kolor HQ       %sColor · 600 dpi%s\n' "$Y" "$R" "$D" "$R"
    printf '   %s[0]%s      Kolor szybki   %sColor · 150 dpi%s\n' "$Y" "$R" "$D" "$R"
    printf '   %s[q]%s      Zakończ\n' "$Y" "$R"
    printf '\n   Wybór %s›%s ' "$C" "$R"
}

# Adaptacyjna korekcja poziomów na podstawie histogramu:
#  - papier (dominujący jasny poziom) -> biel; liczony osobno dla R/G/B = balans bieli
#  - 10. percentyl pikseli "tuszu" (ciemniejszych od papieru o >30) -> czerń
# Ustawia tablicę lvl_args (argumenty dla convert) i opis lvl_info.
auto_levels() {
    local img=$1 mode=$2 ch chans paper black papers=() blacks=()
    lvl_args=(); lvl_info=""
    if [ "$mode" = Color ]; then chans="R G B"; else chans="R"; fi
    for ch in $chans; do
        read -r paper black < <(convert "$img" -sample 25% -channel "$ch" -separate -depth 8 -format %c histogram:info:- \
            | sed -E 's/^ *([0-9]+): *\( *([0-9]+).*/\2 \1/' | awk '
                { c[$1] += $2; t += $2 }
                END {
                    p = 255
                    for (i = 128; i <= 255; i++) if (c[i] > c[p]) p = i
                    for (i = 0; i < p - 30; i++) ink += c[i]
                    b = 0
                    if (ink > t * 0.0005)
                        for (i = 0; i < p - 30; i++) { cum += c[i]; if (cum >= ink * 0.10) { b = i; break } }
                    if (b > 160) b = 160
                    print p, b
                }')
        papers+=("$paper"); blacks+=("$black")
        [ "$mode" = Color ] && lvl_args+=(-channel "$ch")
        lvl_args+=(-level "$(awk -v b="$black" -v p="$paper" 'BEGIN { printf "%.2f%%,%.2f%%", b*100/255, p*100/255 }'),$var_opt_gamma")
    done
    lvl_args+=(+channel)
    if [ "$mode" = Color ]; then
        lvl_info="papier RGB $(IFS=/; echo "${papers[*]}") → biel · czerń $(IFS=/; echo "${blacks[*]}") → 0 · gamma $var_opt_gamma"
    else
        lvl_info="papier ${papers[0]} → biel · czerń ${blacks[0]} → 0 · gamma $var_opt_gamma"
    fi
}

session_summary() {
    printf '\n\n %sSesja zakończona.%s Zeskanowano stron: %s%d%s' "$B" "$R" "$B" "$x" "$R"
    if [ "$x" -gt 0 ]; then
        printf '  %s(oryginały %s, zoptymalizowane %s)%s' "$D" "$(human "$total_orig")" "$(human "$total_opt")" "$R"
    fi
    printf '\n Katalog: %s\n\n' "$var_output_path"
}

cleanup() {
    [ -n "$in_progress" ] && rm -f "$in_progress"
    rm -f "$errlog"
    session_summary
    exit 0
}
trap cleanup INT

do_scan() {
    local res=$1 mode=$2 label=$3
    local base num orig opt t0
    base="scan_${var_site}_D${stamp}"
    num=$(printf "%03d" "$x")
    orig="$var_output_path/${base}_org_$num.$ext"
    opt="$var_output_path/${base}_opt_$num.jpg"

    printf '\n   %s⟳ Skanowanie…%s %s %s(%s · %s dpi)%s\n' "$C" "$R" "$label" "$D" "$mode" "$res" "$R"
    t0=$SECONDS
    in_progress=$orig
    if ! scanimage --resolution "$res" --mode "$mode" --format="$var_format" > "$orig" 2> "$errlog" \
        || [ ! -s "$orig" ]; then
        rm -f "$orig"
        in_progress=""
        printf '   %s✘ Błąd skanowania%s – plik nie został zapisany.\n' "$RED$B" "$R"
        [ -s "$errlog" ] && sed 's/^/     /' "$errlog" | tail -n 3
        return 1
    fi

    # oryginał: obrót i bezstratna kompresja TIFF
    local post=()
    [ "$var_rotate" != 0 ] && post+=(-rotate "$var_rotate")
    [ "$ext" = tiff ] && post+=(-compress lzw)
    [ ${#post[@]} -gt 0 ] && convert "$orig" "${post[@]}" "$orig"

    # wersja zoptymalizowana: JPEG, bez metadanych, max var_opt_max_dpi, korekcja poziomów
    local opt_args=(-strip -interlace JPEG -quality "$var_opt_quality")
    [ "$res" -gt "$var_opt_max_dpi" ] && opt_args+=(-resample "$var_opt_max_dpi")
    if [ "$mode" = Color ]; then
        opt_args+=(-sampling-factor 4:2:0)
    else
        opt_args+=(-colorspace Gray)
    fi
    lvl_info="wyłączona"
    if [ "$var_opt_enhance" = 1 ]; then
        auto_levels "$orig" "$mode"
        opt_args+=("${lvl_args[@]}")
    fi
    convert -units PixelsPerInch -density "$res" "$orig" "${opt_args[@]}" "$opt"
    chmod 664 "$orig" "$opt"
    in_progress=""

    # informacje o plikach
    local w h ow oh size_o size_p opt_dpi saving
    read -r w h < <(identify -format '%w %h' "$orig")
    read -r ow oh < <(identify -format '%w %h' "$opt")
    size_o=$(stat -c%s "$orig")
    size_p=$(stat -c%s "$opt")
    opt_dpi=$(( res > var_opt_max_dpi ? var_opt_max_dpi : res ))
    saving=$(( 100 - size_p * 100 / size_o ))
    total_orig=$(( total_orig + size_o ))
    total_opt=$(( total_opt + size_p ))

    printf '\n   %s✔ Strona %03d zapisana%s  %s%d s · %d×%d mm%s\n' "$G$B" "$((x + 1))" "$R" "$D" \
        "$((SECONDS - t0))" "$(( w * 254 / (res * 10) ))" "$(( h * 254 / (res * 10) ))" "$R"
    printf '     %-11s %s/\n' "Katalog" "$var_output_path"
    printf '     Oryginał    %s\n' "$(basename "$orig")"
    printf '     %-11s %s%9s%s   %d×%d px · %d dpi · %s · %s\n' "" "$B" "$(human "$size_o")" "$R" \
        "$w" "$h" "$res" "$mode" "${ext^^}"
    printf '     %-11s %s\n' "Optymalny" "$(basename "$opt")"
    printf '     %-11s %s%9s%s   %d×%d px · %d dpi · JPEG q%d   %s−%d%%%s\n' "" "$G$B" "$(human "$size_p")" "$R" \
        "$ow" "$oh" "$opt_dpi" "$var_opt_quality" "$G" "$saving" "$R"
    printf '     Korekcja    %s%s%s\n' "$D" "$lvl_info" "$R"

    x=$((x + 1))
}

while :; do
    show_menu
    read -rsn1 key
    case "$key" in
        1)     do_scan 600 Color "Kolor HQ" ;;
        0)     do_scan 150 Color "Kolor szybki" ;;
        "")    do_scan "$var_resolution" "$var_mode" "Standard" ;;
        q|Q)   cleanup ;;
        *)     printf '\n   %sNieznana opcja: %s%s\n' "$RED" "$key" "$R" ;;
    esac
done
