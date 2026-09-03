#!/bin/bash
# Sätter upp det Kundkoll behöver utanför själva appen:
#
#   1. whisper.cpp byggt, med KB-Whisper small + medium och Silero-VAD
#   2. en Pythonmiljö för röstanalysen (torch, speechbrain, pyannote) och MLX
#   3. frivilligt: Ollama med qwen3:8b (insikter) och bge-m3 (betydelsesökning)
#
#   scripts/installera.sh                 # installerar det som saknas
#   scripts/installera.sh --med-ollama    # …och Ollama med modeller
#   scripts/installera.sh --kontrollera   # säger bara vad som saknas
#
# Sökvägarna är de appen letar på (Whisper.Sökvägar och Röstanalys.Sökvägar):
#   ~/Projekt/whisper.cpp och ~/Projekt/transcriber/venv
# Skriptet går att köra om — det som redan finns hoppas över.
set -euo pipefail

WHISPER="$HOME/Projekt/whisper.cpp"
VENV="$HOME/Projekt/transcriber/venv"
PYTHON_VERSION="${KUNDKOLL_PYTHON:-3.12}"

# KBLab lägger ggml-varianterna i samma modellrepo som HF-vikterna.
# Stämmer inte filnamnet längre: öppna sidan och rätta här.
KB_SMALL="https://huggingface.co/KBLab/kb-whisper-small/resolve/main/ggml-model.bin"
KB_MEDIUM="https://huggingface.co/KBLab/kb-whisper-medium/resolve/main/ggml-model.bin"

MED_OLLAMA=0
BARA_KONTROLL=0
for arg in "$@"; do
    case "$arg" in
        --med-ollama) MED_OLLAMA=1 ;;
        --kontrollera) BARA_KONTROLL=1 ;;
        -h|--help) sed -n 2,14p "$0"; exit 0 ;;
        *) echo "okänt argument: $arg" >&2; exit 2 ;;
    esac
done

steg() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
brist() { printf '  ✗ %s\n' "$*"; }

# ---------------------------------------------------------------- kontroll

kontrollera() {
    local fel=0
    steg "verktyg"
    if xcode-select -p >/dev/null 2>&1; then ok "Command Line Tools"; else brist "Command Line Tools saknas (xcode-select --install)"; fel=1; fi
    if command -v swift >/dev/null; then ok "swift $(swift --version 2>/dev/null | head -1 | sed 's/.*version //; s/ .*//')"; else brist "swift saknas"; fel=1; fi
    if command -v brew >/dev/null; then ok "Homebrew"; else brist "Homebrew saknas (https://brew.sh)"; fel=1; fi
    if command -v cmake >/dev/null; then ok "cmake"; else brist "cmake saknas (brew install cmake)"; fel=1; fi

    steg "whisper.cpp i $WHISPER"
    for bin in whisper-server whisper-cli; do
        if [ -x "$WHISPER/build/bin/$bin" ]; then ok "$bin"; else brist "$bin saknas i build/bin"; fel=1; fi
    done
    for m in kb_whisper_ggml_small.bin kb_whisper_ggml_medium.bin ggml-silero-v5.1.2.bin; do
        if [ -s "$WHISPER/models/$m" ]; then ok "models/$m"; else brist "models/$m saknas"; fel=1; fi
    done

    steg "Pythonmiljö i $VENV"
    if [ -x "$VENV/bin/python" ]; then
        ok "python $("$VENV/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
        for paket in torch torchaudio speechbrain pyannote.audio huggingface_hub numpy; do
            if "$VENV/bin/python" -c "import $paket" >/dev/null 2>&1; then ok "$paket"; else brist "$paket saknas"; fel=1; fi
        done
        if [ -x "$VENV/bin/mlx_whisper" ]; then ok "mlx_whisper (engelska möten)"; else brist "mlx_whisper saknas — engelska möten kräver den eller en molnmotor"; fi
    else
        brist "ingen venv"; fel=1
    fi

    steg "modeller för röstanalysen"
    if [ -d "$HOME/.cache/huggingface/hub/models--pyannote--speaker-diarization-3.1" ]; then
        ok "pyannote/speaker-diarization-3.1 i cachen"
    else
        brist "pyannote saknas i cachen — uppdelningen av röster faller tillbaka på klustring (sämre)"
    fi
    if [ -s "$HOME/.cache/speechbrain/spkrec-ecapa-voxceleb/embedding_model.ckpt" ]; then
        ok "speechbrain ECAPA i cachen"
    else
        ok "speechbrain ECAPA hämtas automatiskt vid första körningen"
    fi

    steg "Ollama (frivilligt)"
    if command -v ollama >/dev/null; then
        ok "ollama"
        if curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
            for m in qwen3 bge-m3; do
                if curl -fs http://127.0.0.1:11434/api/tags | grep -q "\"$m"; then ok "modellen $m"; else brist "modellen $m saknas (ollama pull $m)"; fi
            done
        else
            brist "Ollama är inte igång (brew services start ollama)"
        fi
    else
        brist "inte installerat — insikter under samtal och betydelsesökning kräver Ollama"
    fi

    return $fel
}

if [ "$BARA_KONTROLL" = 1 ]; then
    kontrollera && printf '\nAllt appen kräver finns.\n' || printf '\nNågot saknas, se ovan.\n'
    exit 0
fi

# ---------------------------------------------------------------- förutsättningar

steg "förutsättningar"
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Kundkoll är en macOS-app; det här skriptet gör bara nytta på en Mac." >&2
    exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
    echo "Apple Silicon krävs — whisper.cpp med Metal, MLX och mätningarna i docs/ förutsätter det." >&2
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Command Line Tools saknas. Kör:  xcode-select --install  och starta om skriptet när det är klart." >&2
    exit 1
fi
ok "macOS $(sw_vers -productVersion) på Apple Silicon, Command Line Tools finns"

if ! command -v brew >/dev/null; then
    echo "Homebrew saknas. Installera från https://brew.sh och kör om skriptet." >&2
    exit 1
fi
for paket in cmake "python@$PYTHON_VERSION" ffmpeg; do
    if brew list --versions "$paket" >/dev/null 2>&1; then
        ok "$paket finns"
    else
        echo "  installerar $paket"
        brew install "$paket"
    fi
done

# ---------------------------------------------------------------- whisper.cpp

steg "whisper.cpp"
mkdir -p "$(dirname "$WHISPER")"
if [ ! -d "$WHISPER/.git" ]; then
    git clone https://github.com/ggml-org/whisper.cpp "$WHISPER"
else
    ok "redan klonat"
fi
if [ -x "$WHISPER/build/bin/whisper-cli" ] && [ -x "$WHISPER/build/bin/whisper-server" ]; then
    ok "redan byggt"
else
    echo "  bygger (tar några minuter)"
    (cd "$WHISPER" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null \
        && cmake --build build -j --config Release --target whisper-cli whisper-server >/dev/null)
    ok "whisper-cli och whisper-server byggda"
fi

hamta() {  # hamta <url> <fil>
    local url="$1" fil="$2"
    if [ -s "$fil" ]; then ok "$(basename "$fil") finns"; return; fi
    echo "  hämtar $(basename "$fil") …"
    if ! curl -L --fail --progress-bar -o "$fil.del" "$url"; then
        rm -f "$fil.del"
        echo "  kunde inte hämta $url" >&2
        echo "  Öppna modellsidan i webbläsaren, se vad ggml-filen heter, och rätta adressen överst i $0." >&2
        return 1
    fi
    mv "$fil.del" "$fil"
}
mkdir -p "$WHISPER/models"
hamta "$KB_SMALL"  "$WHISPER/models/kb_whisper_ggml_small.bin"
hamta "$KB_MEDIUM" "$WHISPER/models/kb_whisper_ggml_medium.bin"
if [ -s "$WHISPER/models/ggml-silero-v5.1.2.bin" ]; then
    ok "ggml-silero-v5.1.2.bin finns"
else
    # Följer med whisper.cpp; lägger filen i models/.
    (cd "$WHISPER" && bash models/download-vad-model.sh silero-v5.1.2)
fi

# ---------------------------------------------------------------- Pythonmiljön

steg "Pythonmiljö för röstanalysen"
PYBIN="$(brew --prefix "python@$PYTHON_VERSION")/bin/python$PYTHON_VERSION"
mkdir -p "$(dirname "$VENV")"
if [ -x "$VENV/bin/python" ]; then
    ok "venv finns"
else
    "$PYBIN" -m venv "$VENV"
    ok "venv skapad med $("$VENV/bin/python" --version)"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
echo "  installerar torch, speechbrain, pyannote (tar en stund första gången)"
# pyannote 3.x och 4.x fungerar båda med speaker-diarization-3.1, som appen
# använder. speechbrain 1.0.3 + nyare huggingface_hub hanteras i rostanalys.py.
"$VENV/bin/pip" install --quiet \
    torch torchaudio numpy huggingface_hub \
    "speechbrain>=1.0" "pyannote.audio>=3.3,<5"
ok "röstanalysens paket"

# MLX-whisper behövs bara för engelska möten (KB-Whisper översätter dem till
# svenska). Går installationen fel stannar det här inte allt annat.
if [ -x "$VENV/bin/mlx_whisper" ]; then
    ok "mlx_whisper finns"
elif "$VENV/bin/pip" install --quiet mlx-whisper; then
    ok "mlx_whisper (engelska möten)"
else
    brist "mlx-whisper gick inte att installera — engelska möten får gå via en molnmotor. Se docs/INSTALLATION.md."
fi

# ---------------------------------------------------------------- pyannote-modellen

steg "pyannote/speaker-diarization-3.1"
if [ -d "$HOME/.cache/huggingface/hub/models--pyannote--speaker-diarization-3.1" ]; then
    ok "finns i cachen"
else
    TOKEN="${HF_TOKEN:-}"
    if [ -z "$TOKEN" ] && [ -s "$HOME/.cache/huggingface/token" ]; then
        TOKEN="$(cat "$HOME/.cache/huggingface/token")"
    fi
    if [ -z "$TOKEN" ]; then
        brist "hämtas inte: kräver ett Hugging Face-konto som godkänt villkoren."
        cat <<'TEXT'
    1. Skapa konto på huggingface.co och godkänn villkoren på
         https://huggingface.co/pyannote/speaker-diarization-3.1
         https://huggingface.co/pyannote/segmentation-3.0
    2. Skapa en läs-token under Settings → Access Tokens.
    3. Kör:  HF_TOKEN=hf_… scripts/installera.sh
    Utan modellen fungerar appen ändå, men uppdelningen av flera röster i
    samma möte blir sämre (egen klustring i stället för pyannote).
TEXT
    else
        echo "  hämtar modellen (en gång; sedan körs den helt offline)"
        HF_TOKEN="$TOKEN" "$VENV/bin/python" - <<'PY'
import os, warnings
warnings.filterwarnings("ignore")
from pyannote.audio import Pipeline
namn = "pyannote/speaker-diarization-3.1"
token = os.environ["HF_TOKEN"]
try:
    p = Pipeline.from_pretrained(namn, token=token)          # pyannote 4
except TypeError:
    p = Pipeline.from_pretrained(namn, use_auth_token=token)  # pyannote 3
if p is None:
    raise SystemExit("modellen gick inte att ladda — är villkoren godkända för både "
                     "speaker-diarization-3.1 och segmentation-3.0?")
print("  ✓ pyannote-modellen ligger nu i ~/.cache/huggingface")
PY
    fi
fi

# ---------------------------------------------------------------- Ollama

if [ "$MED_OLLAMA" = 1 ]; then
    steg "Ollama"
    if command -v ollama >/dev/null; then ok "ollama finns"; else brew install ollama; fi
    if ! curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        brew services start ollama
        for _ in $(seq 1 20); do
            curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    for m in qwen3:8b bge-m3; do
        echo "  ollama pull $m"
        ollama pull "$m"
    done
fi

# ---------------------------------------------------------------- summering

printf '\n=========================================================\n'
kontrollera && printf '\nAllt appen kräver finns. Bygg nu appen:\n\n    ./scripts/bygg-app.sh\n    open dist/Kundkoll.app\n\n' \
            || printf '\nNågot saknas, se ovan. Kör om skriptet när det är åtgärdat.\n\n'
