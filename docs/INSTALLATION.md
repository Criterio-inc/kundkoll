# Installation

Kundkoll är en nativ macOS-app som lutar sig mot tre saker utanför sig själv:
whisper.cpp för transkriberingen, en Pythonmiljö för röstanalysen, och —
frivilligt — Ollama för insikter under samtal och betydelsesökning. Allt
körs lokalt. Bara chatten går ut på nätet, och bara om du väljer en
molnleverantör.

Det här dokumentet går igenom en tom Mac till fungerande app. Det mesta gör
`scripts/installera.sh`; det som kräver konton eller klick står utskrivet.

## Vad som krävs

| | Krav | Varför |
|---|---|---|
| Dator | Apple Silicon, macOS 26 | ScreenCaptureKit-mikrofonfångst (15+), FoundationModels, Metal i whisper.cpp |
| Verktyg | Command Line Tools, Homebrew | Swift 6.2 för bygget; cmake och Python via brew |
| Disk | ~6 GB | modeller: KB-Whisper 0,5 + 1,5 GB, torch ~2 GB, Ollama-modeller 5 GB till |
| Konto | Hugging Face (gratis) | bara för pyannote-modellen, en enda gång |

Xcode behövs inte. Testramverken följer inte med Command Line Tools, så
proven körs som ett läge i appen (`--test`).

## 1. Verktyg

```bash
xcode-select --install          # Command Line Tools, om de saknas
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
swift --version                 # ska vara 6.2 eller nyare
```

## 2. Allt utanför appen

```bash
git clone https://github.com/Criterio-inc/kundkoll ~/Projekt/kundkoll
cd ~/Projekt/kundkoll
./scripts/installera.sh                # whisper.cpp, modeller, Pythonmiljön
./scripts/installera.sh --med-ollama   # …och Ollama med qwen3:8b + bge-m3
./scripts/installera.sh --kontrollera  # visar bara vad som finns och saknas
```

Skriptet är idempotent: det som redan finns hoppas över, så det går att
köra om efter ett avbrott. Det lägger allt där appen letar:

```
~/Projekt/whisper.cpp/            klonat och byggt (whisper-cli, whisper-server)
  models/kb_whisper_ggml_small.bin    live under samtal
  models/kb_whisper_ggml_medium.bin   arkivpasset efter samtalet
  models/ggml-silero-v5.1.2.bin       VAD — hindrar whisper att hitta på text ur tystnad
~/Projekt/transcriber/venv/       Python med torch, torchaudio, speechbrain, pyannote, mlx-whisper
~/.cache/huggingface/             pyannote/speaker-diarization-3.1 (se nästa steg)
~/.cache/speechbrain/             ECAPA-röstavtryck, hämtas automatiskt vid första körningen
```

Sökvägarna är hårdkodade i `Whisper.Sökvägar` och `Röstanalys.Sökvägar`.
Vill du ha dem någon annanstans: ändra där, eller lägg symlänkar.

### pyannote kräver ett Hugging Face-konto

Modellen som delar upp rösterna i ett möte (`pyannote/speaker-diarization-3.1`)
är gratis men grindad. En gång:

1. Skapa konto på [huggingface.co](https://huggingface.co).
2. Godkänn villkoren på alla tre:
   [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1),
   [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0)
   och [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1).
   Den tredje står inte på 3.1:s modellkort, men pyannote 4 hämtar delar
   av pipelinen därifrån — uppmätt: `403 … community-1 is restricted` med
   bara de två första godkända.
3. Skapa en läs-token under *Settings → Access Tokens*.
4. `HF_TOKEN=hf_… ./scripts/installera.sh`

Efter det körs modellen helt offline (`HF_HUB_OFFLINE=1` i `rostanalys.py`),
och token behövs aldrig igen. Utan modellen fungerar appen ändå: ditt spår
och motpartens är åtskilda av inspelningen, men flera röster på motpartsspåret
delas då upp med egen klustring, som är märkbart sämre. Se `docs/RÖSTANALYS.md`.

### MLX-whisper — bara för engelska möten

KB-Whisper är svensktrimmad och översätter engelska till svenska, oavsett
språkflagga (uppmätt, `docs/VERIFIERAD-STACK.md`). Engelska möten routas
därför automatiskt till MLX, som installeras i samma venv. Faller MLX mot
Metal-kompilatorn («unsupported deferred-static-alloca-size») är det en
känd krock med vissa mlx-versioner:

```bash
~/Projekt/transcriber/venv/bin/pip install "mlx==0.31.2" mlx-whisper
```

Alternativet är en molnmotor (OpenAI eller ElevenLabs) under ⌘, — då lämnar
ljudet datorn, vilket inställningen säger i klartext.

### Ollama (frivilligt)

Två funktioner kräver en lokal modellserver:

- **Insikter under samtal** — `qwen3:8b` bedömer om något som sägs behöver
  slås upp. Uppmätt 12 av 12 rätt utan falska larm (`docs/INSIKTER.md`).
- **Betydelsesökning** — `bge-m3` bäddar in kunskapsbanken lokalt, så att
  chatten hittar «leveranstid» när du frågar om «när det kommer».

`--med-ollama` installerar och hämtar båda. Utan Ollama fungerar appen som
förut: ordsökning i stället för betydelse, och inga insikter under samtal.

## 3. Bygga och starta appen

```bash
./scripts/bygg-app.sh        # dist/Critero-kundkoll.app
open dist/Critero-kundkoll.app
```

Bygget signeras **ad hoc** om inget certifikat finns. Det fungerar, men
macOS kopplar behörigheter till signaturen, så mikrofon och skärminspelning
måste beviljas om efter varje ombygge. Ligger exakt ett Developer
ID-certifikat i nyckelringen använder skriptet det av sig självt; finns
flera anges vilket med `KUNDKOLL_SIGNERING`:

```bash
KUNDKOLL_SIGNERING="Developer ID Application: Namn (XXXXXXXXXX)" ./scripts/bygg-app.sh
```

Ett personligt Apple Developer-konto duger: Developer ID ges till
individer också, och appen körs bara på din egen dator. Certifikatet
skapas i Xcode → Settings → Accounts → Manage Certificates → + →
Developer ID Application, och syns sedan i
`security find-identity -v -p codesigning`.

Provsviten körs i terminalen, utan Xcode:

```bash
swift build
.build/arm64-apple-macosx/debug/Kundkoll --test
```

## 4. Behörigheter

macOS frågar vid första användningen. Under *Systeminställningar → Integritet
och säkerhet*:

| Behörighet | Krävs för | Utan den |
|---|---|---|
| Mikrofon | ditt spår | ingen inspelning |
| Skärminspelning | datorljudet — ScreenCaptureKit fångar bara ljud, ingen bild sparas | inget motpartsspår |
| Kalender | möten kopplade till kund, «Förbered», notis en kvart före | inga möten syns |
| Kontakter | personer ur adressboken | kontakter skrivs upp för hand |
| Påminnelser | uppgifter speglade till Påminnelser | knappen gör inget |
| Automatisering → Mail | mejl per kund, uppföljningsutkast | mejlfliken tom |

Skärminspelning är den som förvånar: den behövs för att en `SCStream` måste
ha ett innehållsfilter, även när bara ljudet används. Appen fångar minsta
möjliga yta och kastar videorutorna.

## 5. Första starten

1. **⌘, → Modell för kundchatten.** Välj leverantör. Lokalt (Ollama, LM
   Studio, MLX) lämnar inget datorn; OpenRouter, Anthropic, OpenAI och Azure
   kräver nyckel, som sparas i nyckelringen. Knappen «Prova» gör ett riktigt
   anrop så att felet visar sig här och inte mitt i en fråga.
2. **Ditt namn** i samma dialog — så tilltalar chatten dig. Tomt betyder
   namnet på macOS-kontot, som också används i uppföljningsmejlens signatur
   och för att känna igen dig i kalendermötens deltagarlistor.
3. **Skapa en kund** i sidopanelen, eller en mapp under `~/Documents/Kunder`
   — filsystemet är sanningen, ingen databas. Varje kund är en Obsidian-vault.
4. **Spela in** något kort och se att live-transkriptet kommer. Kommer inget:
   `./scripts/installera.sh --kontrollera` säger vad som saknas, och samma
   brister står i ⌘, under transkribering.

## Felsökning

**«whisper-server saknas» trots att whisper.cpp är byggt.** Binären heter
`whisper-cli`, inte `main` — `main` är en avvecklad stub som returnerar
direkt. Bygg med `cmake --build build --target whisper-cli whisper-server`.

**Live-transkriptet är tomt men arkivet fullständigt.** Taldetekteringen
mäter mot rummets bakgrund; en mikrofon med mycket lägre nivå än väntat kan
falla under tröskeln. Se avsnittet i `docs/VERIFIERAD-STACK.md` innan du
ändrar någon konstant.

**Röster delas inte upp.** Kontrollera att pyannote ligger i cachen
(`--kontrollera`). Loggen från Pythonprocessen går till stderr och syns i
Konsol-appen under Critero-kundkoll.

**Engelskt möte blev svenska.** Mötet transkriberades med KB-modellen. Öppna
mötet, välj engelska och «transkribera om»; det kräver MLX eller en
molnmotor.

**Behörigheter försvinner efter varje bygge.** Signera med ett Developer
ID via `KUNDKOLL_SIGNERING`, eller acceptera att bevilja om.

**Datorn blir trög under möten.** Kör `pgrep -fl whisper-server` när appen
inte är igång: listan ska vara tom. Är den inte det har gamla servrar blivit
kvar; `pkill -f whisper-server` och starta om appen. Byt sedan insiktsmodell
till `qwen3:4b` under ⌘, — den klarar samma facit som 8b och tar 3,8 GB i
stället för 6,5 GB. Siffrorna står i `docs/VERIFIERAD-STACK.md`.

**Skärminspelning står på, men appen frågar ändå.** macOS knyter posten
till den signatur appen hade när den gavs. Byts signaturen (ad hoc → Developer
ID, eller ett nytt ad hoc-bygge) matchar posten inte längre, fast reglaget
ser påslaget ut. Nollställ posten och ge behörigheten igen:

```bash
tccutil reset ScreenCapture se.critero.kundkoll
```

Starta appen, tryck «Spela in», slå på Critero-kundkoll i dialogen som
öppnas och starta om appen. Godkännandet gäller först efter omstart.
