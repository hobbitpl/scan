#!/bin/bash
# Skanowanie z CLI (SANE). Każdy skan zapisywany jest jako oryginał
# oraz jako wersja zoptymalizowana (JPEG, mniejszy rozmiar).
clear
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
. "$DIR/local.config"

# wartości domyślne, jeśli brak w local.config
: "${var_resolution:=300}" "${var_mode:=Gray}" "${var_format:=tiff}" "${var_rotate:=0}" "${var_site:=$HOSTNAME}"
: "${var_opt_quality:=80}"   # jakość JPEG wersji zoptymalizowanej
: "${var_opt_max_dpi:=300}"  # wersja zoptymalizowana nie przekracza tej rozdzielczości (nie dotyczy Color)
: "${var_opt_enhance:=1}"    # 1 = automatyczna korekcja bieli/czerni w wersji zoptymalizowanej
: "${var_opt_gamma:=0.8}"    # < 1 przyciemnia półtony (pismo, ołówek), 1 = bez zmian – tylko Gray
: "${var_opt_color_gamma:=1.0}"  # gamma dla skanów kolorowych (1 = bez zmian, > 1 rozjaśnia)
: "${var_adf_source:=ADF Front}"  # źródło dla skanowania z podajnika (ADF Front / ADF Duplex)
: "${var_adf_color_resolution:=300}"  # dpi dla ADF w kolorze

case "$var_format" in
    jpeg) ext=jpg ;;
    *)    ext=$var_format ;;
esac

stamp=$(date +%Y_%m_%d_T%H_%M_%S)
x=0
total_orig=0
total_opt=0
in_progress=""
bg_pid=""
errlog=$(mktemp)   # stderr scanimage (błędy + "Progress: x%")
monlog=$(mktemp)   # stderr convert -monitor
tmpout=$(mktemp)   # stdout poleceń w tle (lista skanerów, histogram)

# kolory
B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; RED=$'\e[31m'

human() { numfmt --to=iec-i --suffix=B --format=%.1f "$1"; }

# ---------------------------------------------------------------------------
# Paski postępu
# ---------------------------------------------------------------------------
BAR_W=28
BAR_FULL=$(printf '█%.0s' $(seq 60))
BAR_EMPTY=$(printf '░%.0s' $(seq 60))
BAR_PART=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
if [ "${#BAR_FULL}" -ne 60 ]; then   # brak UTF-8 – wersja ASCII
    BAR_FULL=$(printf '#%.0s' $(seq 60)); BAR_EMPTY=$(printf -- '-%.0s' $(seq 60)); BAR_PART=("" "" "" "" "" "" "" "")
fi
tick=0

now_ms() { local t=${EPOCHREALTIME/[.,]/}; echo $(( t / 1000 )); }
fmt_secs() { printf '%d.%d s' $(( $1 / 1000 )) $(( $1 % 1000 / 100 )); }

# draw_bar <promile 0–1000 | -1 = nieokreślony> <etykieta> <opis> [kolor]
draw_bar() {
    local p=$1 label=$2 info=$3 col=${4:-$C} bar pct n r rest max
    if [ "$p" -lt 0 ]; then
        # brak danych o postępie: blok przesuwający się tam i z powrotem
        local span=$(( BAR_W - 6 )) pos=$(( tick % (2 * (BAR_W - 6)) ))
        [ $pos -gt $span ] && pos=$(( 2 * span - pos ))
        bar="$D${BAR_EMPTY:0:pos}$R$col${BAR_FULL:0:6}$R$D${BAR_EMPTY:0:span-pos}$R"
        pct='    '
    else
        [ "$p" -gt 1000 ] && p=1000
        n=$(( p * BAR_W * 8 / 1000 )); r=$(( n % 8 )); n=$(( n / 8 ))
        rest=$(( BAR_W - n ))
        bar="$col${BAR_FULL:0:n}"
        if [ $rest -gt 0 ] && [ -n "${BAR_PART[r]}" ]; then
            bar+="${BAR_PART[r]}"; rest=$(( rest - 1 ))
        fi
        bar+="$R$D${BAR_EMPTY:0:rest}$R"
        pct=$(printf '%3d%%' $(( p / 10 )))
    fi
    max=$(( ${COLUMNS:-100} - BAR_W - 28 )); [ $max -lt 0 ] && max=0
    printf '\r\e[K   %-14s %s %s%s%s  %s%s%s' "$label" "$bar" "$B" "$pct" "$R" "$D" "${info:0:max}" "$R"
}

# bar_end <ok|fail> <etykieta> <opis> – stan końcowy paska + nowa linia
bar_end() {
    if [ "$1" = ok ]; then
        draw_bar 1000 "$2" "$3" "$G"; printf ' %s✔%s\n' "$G" "$R"
    else
        draw_bar 0 "$2" "$3" "$RED"; printf ' %s✘%s\n' "$RED" "$R"
    fi
}

# track <pid> <rodzaj> <od> <do> <etykieta> <etap> [plik wyjściowy]
# Odświeża pasek, dopóki proces działa; zwraca jego kod wyjścia.
#  scan – postęp z "Progress: x%" (scanimage -p) w errlog
#  im   – postęp z convert -monitor (monlog): wczytywanie 0–40%, operacje 40–70%, zapis 70–100%
#  none – brak danych o postępie (animacja + czas)
track() {
    local pid=$1 kind=$2 lo=$3 hi=$4 label=$5 stage=$6 file=$7
    local t0 last v i d f p phase info rest pmax=$lo
    t0=$(now_ms)
    COLUMNS=$(tput cols 2>/dev/null || echo 100)
    bg_pid=$pid
    while kill -0 "$pid" 2>/dev/null; do
        f=-1; info=$stage
        case $kind in
            scan)
                last=$(tail -c 80 "$errlog" | tr '\r' '\n' | grep -o 'Progress: [0-9.]*' | tail -n 1)
                v=${last#Progress: }
                if [ -n "$v" ]; then
                    i=${v%%.*}; d=0; [[ $v == *.* ]] && d=${v#*.} && d=${d:0:1}
                    f=$(( 10#${i:-0} * 10 + 10#${d:-0} ))
                fi
                if [ "$f" -le 0 ]; then
                    f=-1; info="kalibracja i rozgrzewanie lampy"
                else
                    info="odczyt $(human "$(stat -c%s "$file" 2>/dev/null || echo 0)")"
                fi ;;
            im)
                last=$(tail -c 300 "$monlog" | tr '\r' '\n' | grep ' of ' | tail -n 1)
                rest=${last##*]: }
                if [[ $rest =~ ^([0-9]+)\ of\ ([0-9]+) ]] && [ "${BASH_REMATCH[2]}" -gt 0 ]; then
                    f=$(( BASH_REMATCH[1] * 1000 / BASH_REMATCH[2] ))
                    phase=${last%%\[*}
                    case $phase in
                        load*) f=$(( f * 400 / 1000 ));       info="$stage · wczytywanie" ;;
                        save*) f=$(( 700 + f * 300 / 1000 )); info="$stage · zapis" ;;
                        *)     f=$(( 400 + f * 300 / 1000 )); info="$stage · przetwarzanie" ;;
                    esac
                fi ;;
        esac
        if [ "$f" -ge 0 ]; then p=$(( lo + (hi - lo) * f / 1000 )); else p=-1; fi
        # pasek nie cofa się (kolejne fazy convert raportują postęp od zera)
        if [ "$p" -ge 0 ] || [ "$lo" -gt 0 ]; then
            [ "$p" -lt "$pmax" ] && p=$pmax
            pmax=$p
        fi
        draw_bar "$p" "$label" "$info · $(fmt_secs $(( $(now_ms) - t0 )))"
        tick=$(( tick + 1 ))
        sleep 0.1
    done
    wait "$pid"
    local rc=$?
    bg_pid=""
    return $rc
}

# ---------------------------------------------------------------------------
# Wykrycie skanera: var_device z local.config, jeśli jest podłączony;
# w przeciwnym razie pierwszy znaleziony (adres USB zmienia się po przełożeniu kabla).
# ---------------------------------------------------------------------------
printf '\e[?25l\n'
detect_t0=$(now_ms)
scanimage -f '%d|%v|%m|%t%n' > "$tmpout" 2>/dev/null &
track $! none -1 -1 "Wykrywanie" "szukanie skanerów"
device=""; scanner_name=""; device_note=""
while IFS='|' read -r d v m t; do
    [ -z "$d" ] && continue
    if [ -z "$device" ] || [ "$d" = "$var_device" ]; then
        device=$d; scanner_name="$v $m"
    fi
done < "$tmpout"
if [ -z "$device" ]; then
    bar_end fail "Wykrywanie" "nie znaleziono skanera"
    printf '\e[?25h\n   %s✘ Nie znaleziono skanera%s (scanimage -L). Sprawdź zasilanie i USB.\n\n' "$RED$B" "$R"
    rm -f "$errlog" "$monlog" "$tmpout"
    exit 1
fi
bar_end ok "Wykrywanie" "$scanner_name · $(fmt_secs $(( $(now_ms) - detect_t0 )))"
printf '\e[?25h'
[ -n "$var_device" ] && [ "$device" != "$var_device" ] && device_note="var_device=$var_device niedostępny"

show_menu() {
    local header
    header=$(printf "SKANER  @%s   strona %03d   %s" "$var_site" "$((x + 1))" "$(date +%H:%M)")
    printf '\n %s╭────────────────────────────────────────────────╮%s\n' "$C" "$R"
    printf ' %s│%s  %s%-46s%s%s│%s\n' "$C" "$R" "$B" "$header" "$R" "$C" "$R"
    printf ' %s│%s  %-46.46s%s│%s\n' "$C" "$R" "$scanner_name" "$C" "$R"
    printf ' %s│%s  %s%-46.46s%s%s│%s\n' "$C" "$R" "$D" "$device" "$R" "$C" "$R"
    printf ' %s╰────────────────────────────────────────────────╯%s\n' "$C" "$R"
    printf '   %s[Enter]%s  Standard       %s%s · %s dpi%s\n' "$Y" "$R" "$D" "$var_mode" "$var_resolution" "$R"
    printf '   %s[1]%s      Kolor HQ       %sColor · 600 dpi%s\n' "$Y" "$R" "$D" "$R"
    printf '   %s[0]%s      Kolor szybki   %sColor · 150 dpi%s\n' "$Y" "$R" "$D" "$R"
    printf '   %s[a]%s      ADF            %s%s · %s dpi · %s · wszystkie strony%s\n' "$Y" "$R" "$D" "$var_mode" "$var_resolution" "$var_adf_source" "$R"
    printf '   %s[c]%s      ADF kolor      %sColor · %s dpi · %s · wszystkie strony%s\n' "$Y" "$R" "$D" "$var_adf_color_resolution" "$var_adf_source" "$R"
    printf '   %s[q/Esc]%s  Zakończ\n' "$Y" "$R"
    [ -n "$device_note" ] && printf '\n   %s! %s – używam %s%s\n' "$Y" "$device_note" "$device" "$R"
    printf '\n   Wybór %s›%s ' "$C" "$R"
}

# Adaptacyjna korekcja poziomów na podstawie histogramu.
# Gray (dokumenty): papier (dominujący jasny poziom) -> biel,
#   10. percentyl pikseli "tuszu" (ciemniejszych od papieru o >30) -> czerń, gamma var_opt_gamma.
# Color (zdjęcia, kolorowe dokumenty): łagodnie, bez przyciemniania –
#   biel = papier liczony osobno dla R/G/B (balans bieli); gdy brak wyraźnego tła papieru
#   (< 1% pikseli w szczycie) biel = 99,5. percentyl; czerń = 0,5. percentyl całego
#   obrazu (max 40), więc obcinane są tylko skrajne cienie; gamma var_opt_color_gamma.
# auto_levels <obraz> <tryb> <od> <do> – zakres paska postępu w promilach.
# Ustawia tablicę lvl_args (argumenty dla convert) i opis lvl_info.
auto_levels() {
    local img=$1 mode=$2 lo=$3 hi=$4 ch chans paper black gamma papers=() blacks=() n=0 cnt
    lvl_args=(); lvl_info=""
    if [ "$mode" = Color ]; then chans="R G B"; cnt=3; gamma=$var_opt_color_gamma; else chans="R"; cnt=1; gamma=$var_opt_gamma; fi
    for ch in $chans; do
        convert -monitor "$img" -sample 25% -channel "$ch" -separate -depth 8 -format %c histogram:info:"$tmpout" 2> "$monlog" &
        track $! im $(( lo + (hi - lo) * n / cnt )) $(( lo + (hi - lo) * (n + 1) / cnt )) \
            "Optymalizacja" "histogram$([ "$mode" = Color ] && echo " $ch")"
        n=$(( n + 1 ))
        read -r paper black < <(sed -E 's/^ *([0-9]+): *\( *([0-9]+).*/\2 \1/' "$tmpout" | awk -v mode="$mode" '
                { c[$1] += $2; t += $2 }
                END {
                    p = 255
                    for (i = 128; i <= 255; i++) if (c[i] > c[p]) p = i
                    b = 0
                    if (mode == "Color") {
                        if (c[p] < t * 0.01) {
                            cum = 0
                            for (i = 255; i >= 0; i--) { cum += c[i]; if (cum >= t * 0.005) { p = i; break } }
                        }
                        cum = 0
                        for (i = 0; i < 256; i++) { cum += c[i]; if (cum >= t * 0.005) { b = i; break } }
                        if (b > 40) b = 40
                        if (p < 128) p = 255
                    } else {
                        for (i = 0; i < p - 30; i++) ink += c[i]
                        if (ink > t * 0.0005)
                            for (i = 0; i < p - 30; i++) { cum += c[i]; if (cum >= ink * 0.10) { b = i; break } }
                        if (b > 160) b = 160
                    }
                    print p, b
                }')
        papers+=("$paper"); blacks+=("$black")
        [ "$mode" = Color ] && lvl_args+=(-channel "$ch")
        lvl_args+=(-level "$(awk -v b="$black" -v p="$paper" 'BEGIN { printf "%.2f%%,%.2f%%", b*100/255, p*100/255 }'),$gamma")
    done
    lvl_args+=(+channel)
    if [ "$mode" = Color ]; then
        lvl_info="biel RGB $(IFS=/; echo "${papers[*]}") → 255 · czerń $(IFS=/; echo "${blacks[*]}") → 0 · gamma $gamma"
    else
        lvl_info="papier ${papers[0]} → biel · czerń ${blacks[0]} → 0 · gamma $gamma"
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
    # procesy w tle nie dostają SIGINT od Ctrl+C – trzeba je zatrzymać ręcznie
    [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null && wait "$bg_pid" 2>/dev/null
    [ -n "$in_progress" ] && rm -f "$in_progress"
    rm -f "$errlog" "$monlog" "$tmpout"
    printf '\e[?25h'
    session_summary
    exit 0
}
trap cleanup INT

do_scan() {
    # zwraca: 0 = OK, 1 = błąd, 2 = podajnik ADF pusty
    local res=$1 mode=$2 label=$3 source=$4
    local base num orig opt t0 t1
    base="scan_${var_site}_D${stamp}"
    num=$(printf "%03d" "$x")
    orig="$var_output_path/${base}_org_$num.$ext"
    opt="$var_output_path/${base}_opt_$num.jpg"

    printf '\n   %s⟳ %s%s %s(%s · %s dpi%s)%s\n' "$C" "$label" "$R" "$D" "$mode" "$res" "${source:+ · $source}" "$R"
    printf '\e[?25l'
    t0=$SECONDS
    t1=$(now_ms)
    in_progress=$orig
    local src_args=()
    [ -n "$source" ] && src_args=(--source "$source")
    scanimage -d "$device" "${src_args[@]}" -p --resolution "$res" --mode "$mode" --format="$var_format" \
        > "$orig" 2> "$errlog" &
    if ! track $! scan 0 1000 "Skanowanie" "" "$orig" || [ ! -s "$orig" ]; then
        rm -f "$orig"
        in_progress=""
        if [ -n "$source" ] && grep -qi "out of documents\|no docs" "$errlog"; then
            printf '\r\e[K\e[1A\e[K\e[1A\e[K\e[?25h'   # usuń nagłówek pustej strony
            return 2
        fi
        bar_end fail "Skanowanie" "plik nie został zapisany"
        printf '\e[?25h   %s✘ Błąd skanowania%s\n' "$RED$B" "$R"
        tr '\r' '\n' < "$errlog" | grep -v '^Progress:' | grep -v '^$' | tail -n 3 | sed 's/^/     /'
        return 1
    fi
    bar_end ok "Skanowanie" "$(human "$(stat -c%s "$orig")") · $(fmt_secs $(( $(now_ms) - t1 )))"

    # podział paska optymalizacji: kompresja oryginału / histogram / JPEG (wagi ~ czas pracy)
    local post=() w_post=0 w_hist=0 w_opt=4 w_all p1 p2
    [ "$var_rotate" != 0 ] && post+=(-rotate "$var_rotate")
    [ "$ext" = tiff ] && post+=(-compress lzw)
    [ ${#post[@]} -gt 0 ] && w_post=3
    if [ "$var_opt_enhance" = 1 ]; then
        if [ "$mode" = Color ]; then w_hist=3; else w_hist=1; fi
    fi
    w_all=$(( w_post + w_hist + w_opt ))
    p1=$(( w_post * 1000 / w_all ))
    p2=$(( (w_post + w_hist) * 1000 / w_all ))
    t1=$(now_ms)

    # oryginał: obrót i bezstratna kompresja TIFF
    if [ ${#post[@]} -gt 0 ]; then
        convert -monitor "$orig" "${post[@]}" "$orig" 2> "$monlog" &
        track $! im 0 "$p1" "Optymalizacja" "oryginał$([ "$ext" = tiff ] && echo " LZW")"
    fi

    # wersja zoptymalizowana: JPEG, bez metadanych, max var_opt_max_dpi, korekcja poziomów
    local opt_args=(-strip -interlace JPEG -quality "$var_opt_quality")
    local opt_dpi=$res
    if [ "$mode" != Color ] && [ "$res" -gt "$var_opt_max_dpi" ]; then
        opt_dpi=$var_opt_max_dpi
        opt_args+=(-resample "$opt_dpi")
    fi
    if [ "$mode" = Color ]; then
        opt_args+=(-sampling-factor 4:2:0)
    else
        opt_args+=(-colorspace Gray)
    fi
    lvl_info="wyłączona"
    if [ "$var_opt_enhance" = 1 ]; then
        auto_levels "$orig" "$mode" "$p1" "$p2"
        opt_args+=("${lvl_args[@]}")
    fi
    convert -monitor -units PixelsPerInch -density "$res" "$orig" "${opt_args[@]}" "$opt" 2> "$monlog" &
    track $! im "$p2" 1000 "Optymalizacja" "JPEG"
    bar_end ok "Optymalizacja" "$(fmt_secs $(( $(now_ms) - t1 )))"
    printf '\e[?25h'
    chmod 664 "$orig" "$opt"
    in_progress=""

    # informacje o plikach
    local w h ow oh size_o size_p saving
    read -r w h < <(identify -format '%w %h' "$orig")
    read -r ow oh < <(identify -format '%w %h' "$opt")
    size_o=$(stat -c%s "$orig")
    size_p=$(stat -c%s "$opt")
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

# skanowanie z podajnika ADF do wyczerpania kartek
scan_adf() {
    local res=$1 mode=$2 label=$3 n=0 rc
    while :; do
        do_scan "$res" "$mode" "$label strona $((n + 1))" "$var_adf_source"
        rc=$?
        [ $rc -ne 0 ] && break
        n=$((n + 1))
    done
    if [ $rc -eq 2 ]; then
        if [ $n -eq 0 ]; then
            printf '   %s! Podajnik ADF pusty%s – włóż dokumenty.\n' "$Y$B" "$R"
        else
            printf '   %s✔ ADF: zeskanowano %d str.%s – podajnik pusty.\n' "$G$B" "$n" "$R"
        fi
    fi
}

while :; do
    show_menu
    read -rsn1 key || cleanup
    case "$key" in
        1)     do_scan 600 Color "Kolor HQ" ;;
        0)     do_scan 150 Color "Kolor szybki" ;;
        "")    do_scan "$var_resolution" "$var_mode" "Standard" ;;
        a|A)   scan_adf "$var_resolution" "$var_mode" "ADF" ;;
        c|C)   scan_adf "$var_adf_color_resolution" Color "ADF kolor" ;;
        q|Q)   cleanup ;;
        $'\e')
            # sam Esc kończy; strzałki/F1… to Esc + dalsze znaki – ignoruj
            read -rsn5 -t 0.05 rest
            [ -z "$rest" ] && cleanup ;;
        *)     printf '\n   %sNieznana opcja: %s%s\n' "$RED" "$key" "$R" ;;
    esac
done
