#!/bin/bash
# Bygger Critero-kundkoll.app. Xcode behövs inte — Command Line Tools räcker.
set -euo pipefail
cd "$(dirname "$0")/.."

KONFIG="${1:-release}"
# Namnet som syns i Finder, menyraden och behörighetsdialogerna. Det
# tekniska målet i Package.swift heter fortfarande Kundkoll.
APP="dist/Critero-kundkoll.app"
# Eget certifikat: KUNDKOLL_SIGNERING="Developer ID Application: Ditt AB (XXXXXXXXXX)"
# Utan certifikat signeras appen ad hoc — det fungerar, men macOS frågar om
# mikrofon och skärminspelning på nytt efter varje ombygge.
IDENTITET="${KUNDKOLL_SIGNERING:-}"
# Giltiga Developer ID i nyckelringen, rader som «1) <hash> "Developer ID Application: …"».
# «|| true» överallt: under set -e dödar en grep utan träff annars hela skriptet.
GILTIGA="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' || true)"
if [ -z "$IDENTITET" ]; then
    # Finns exakt ett namn används det utan att behöva anges — ett personligt
    # utvecklarkonto duger lika bra som ett företags.
    NAMN="$(printf '%s\n' "$GILTIGA" | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' | sort -u || true)"
    if [ -n "$NAMN" ] && [ "$(printf '%s\n' "$NAMN" | grep -c . || true)" -eq 1 ]; then
        IDENTITET="$NAMN"
    fi
fi
# Signeras med certifikatets hash, inte namnet. Samma certifikat kan ligga två
# gånger i nyckelringen, och då svarar codesign «ambiguous» på namnet — uppmätt.
HASH=""
if [ -n "$IDENTITET" ]; then
    HASH="$(printf '%s\n' "$GILTIGA" | grep -F "\"$IDENTITET\"" | head -1 | awk '{print $2}' || true)"
fi

echo "→ kompilerar ($KONFIG)"
swift build -c "$KONFIG" --disable-sandbox

# Bash tillåter bara ASCII i variabelnamn, till skillnad från zsh.
BIN="$(swift build -c "$KONFIG" --show-bin-path)/Kundkoll"

echo "→ paketerar"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kundkoll"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Kundkoll.icns "$APP/Contents/Resources/Kundkoll.icns"
# Röstanalysen körs som en Pythonprocess; skriptet måste följa med appen.
cp scripts/rostanalys.py "$APP/Contents/Resources/rostanalys.py"
cp Resources/mail-sok.applescript "$APP/Contents/Resources/mail-sok.applescript"
cp Resources/mail-bilagor.applescript "$APP/Contents/Resources/mail-bilagor.applescript"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Provsviten går på varje bygge. Den var förut ett löfte i README utan
# mekanism; en ändring som fäller ett prov ska inte bli en app i dist.
# KUNDKOLL_UTAN_PROV=1 hoppar över, för snabba ombyggen under felsökning.
if [ -z "${KUNDKOLL_UTAN_PROV:-}" ]; then
    echo "→ provsviten"
    PROVLOGG="$(mktemp -t kundkoll-prov)"
    if "$APP/Contents/MacOS/Kundkoll" --test > "$PROVLOGG" 2>&1; then
        tail -1 "$PROVLOGG" | sed 's/^/  /'
    else
        echo "  provsviten föll — appen paketeras inte. Sista raderna:"
        grep -v '✓' "$PROVLOGG" | tail -25 | sed 's/^/  /'
        rm -rf "$APP"
        exit 1
    fi
fi

echo "→ signerar"
# En stabil signatur gör att macOS kommer ihåg beviljade behörigheter
# mellan ombyggen i stället för att fråga om mikrofon och skärminspelning varje gång.
if [ -n "$HASH" ]; then
    echo "  med $IDENTITET ($HASH)"
    codesign --force --deep --options runtime --timestamp=none \
        --entitlements Resources/Kundkoll.entitlements \
        --sign "$HASH" "$APP"
else
    if [ -n "$IDENTITET" ]; then
        echo "  (certifikatet «$IDENTITET» hittades inte i nyckelringen — signerar ad hoc)"
    else
        echo "  (inget certifikat angivet i KUNDKOLL_SIGNERING — signerar ad hoc, behörigheter kan behöva ges om vid varje bygge)"
    fi
    codesign --force --deep --sign - \
        --entitlements Resources/Kundkoll.entitlements "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
echo "→ klart: $APP"
