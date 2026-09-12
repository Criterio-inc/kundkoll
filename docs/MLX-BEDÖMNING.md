# MLX i stället för llama.cpp för den lokala modellen

Bedömning 2026-09-12, gjord utan tillgång till datorn. Inget här är uppmätt;
det som är uppmätt står i `docs/VERIFIERAD-STACK.md` och i
`docs/matningar/`. Frågan var ett råd från en annan Claude-session:

> Gör det här först, gratis: byt från Ollama till MLX (via LM Studio eller
> mlx-lm). MLX är 20–30 % snabbare än llama.cpp och upp till 50 % snabbare än
> Ollama på Apple Silicon. Det kan ensamt göra din nuvarande Air dräglig nog
> att skjuta köpet på framtiden.

**Kort svar: värt att prova, men inte så som rådet säger.** Det som gör
datorn seg är enligt repots egna mätningar minnet, inte beräkningsmotorn, och
MLX minskar inte minnesbehovet. Och den billiga MLX-testen finns numera inuti
Ollama, så varken LM Studio eller mlx-lm behövs för att få svar.

## Vad repots siffror säger

Mätt på en M4 med 16 GB medan Teams låg igång (`docs/VERIFIERAD-STACK.md`,
`docs/matningar/2026-09-07-qwen35-4b.log`):

| Mätning | Värde |
|---|---|
| Insiktsmodell qwen3:8b i minnet | 6,5 GB |
| Insiktsmodell qwen3:4b i minnet | 3,8 GB |
| Växlingsfilen när 8b laddades | växte 2 GB |
| Växlingsfil under en 50-minutersinspelning | 20 GB |
| Delanteckning med qwen3 | 4,5 tokens per sekund |
| Sammanfattning av 50-minutersmötet, qwen3.5:4b | 592 s |

En M4 med 120 GB/s minnesbandbredd borde skriva en 4b-modell i fyrbitars
kvantisering i storleksordningen 30 tokens per sekund och en 8b-modell runt
15. Uppmätt 4,5 betyder att modellen låg delvis i växlingsfilen. Den
flaskhalsen flyttar inte med bytet av motor: en modell i MLX-format väger
ungefär lika mycket som samma modell i GGUF.

Två saker i koden förvärrar bilden, och båda är gratis att åtgärda:

- **Två olika modeller ligger i minnet samtidigt under ett möte.** Sedan
  dbec3d4 är chattmodellen `qwen3.5:4b` (`Leverantör.lokal.standardmodell`)
  och insiktsmodellen `qwen3:4b` (`Insikter.standardmodell`). Under ett möte
  anropas båda, och Ollama håller båda laddade. Tabellen med 3,8 GB mättes
  när samma modell gjorde allt, så verklig kostnad i dag är snarare 7 GB
  plus whisper och Teams. Loggen visar att qwen3.5:4b klarade insiktsfacit
  13 av 13, så en modell för båda uppdragen sparar en hel modell i minnet
  mot ungefär 1,4 s längre median per granskning.
- **Qwen3.5 finns som 4b och 9b, inte 8b.** qwen3.5:9b är 6,6 GB i Q4_K_M,
  alltså samma klass som qwen3:8b, som docs redan dömt ut på 16 GB.

## Vad MLX ger och inte ger

**Hastighet.** Tredjepartsmätningar ligger på 15 till 40 procent snabbare
generering än llama.cpp på samma Apple Silicon, mer i prompt-behandlingen.
Ollamas egna siffror, 57 procent snabbare prefill och 93 procent snabbare
decode, gäller en MoE-modell på en M5 Max med neurala acceleratorer i GPU:n
som M4 saknar. För en tät 4b-modell på en M4 är det lägre spannet rimligt.
På sammanfattningen på 592 s vore det kanske 1,5 till 3 minuter, förutsatt
att datorn inte växlar.

**Ollama har redan MLX.** Sedan 0.19 (mars 2026) finns en MLX-motor i
Ollama, och modellerna heter `qwen3.5:4b-mlx` och `qwen3.5:9b-mlx` i
biblioteket. Hela integrationen i appen, `/api/chat`, `format`, `think`,
`/api/tags` och `/api/embed`, fungerar oförändrad. Tre förbehåll:

- Strukturerad utdata, som insikterna bygger på, ignorerades tyst av
  MLX-motorn fram till en fix i 0.33.1 (26 augusti 2026). Kräv minst 0.34.0.
  Den begränsade avkodningen halverar hastigheten enligt pull requesten, så
  insikterna vinner troligen inget på MLX.
- Insiktsmodellen qwen3:4b finns inte i MLX-variant, bara Qwen3.5 och nyare.
- Att MLX-motorn kräver 32 GB, som flera bloggar skrev, gällde
  förhandsversionen. Dagens krav gick inte att verifiera; kontrollera i
  serverloggen att modellen faktiskt körs på mlx.

**LM Studio** har MLX-motor och stödjer JSON-schema, men chatten skickar
`reasoning_effort: none` för att stänga av tänkandet, och LM Studio känner
inte fältet. Det finns öppna buggar där Qwen3.5 tänker ändå och äter hela
`max_tokens`, alltså 97-sekundersfelet i `docs/VERIFIERAD-STACK.md`.
Dessutom går insikter, betydelsesökning och diagnosen via Ollamas eget API.
Pekar man chattadressen på port 1234 räknar `Modellval.lokalBas` ut att
insikter och inbäddning ska fråga samma server. `Insikter.tillgänglig`
godtar ett 404-svar som «igång», varje granskning faller tyst i
`Liveinsikter.granska`, och sökningen går tillbaka till BM25 utan att säga
något. Bara diagnosen avslöjar det. Ett byte till LM Studio kräver alltså en
adapter för tre kodvägar innan det ens går att jämföra.

**mlx_lm.server** saknar JSON-schema och inbäddningar och passar inte alls.

## Provordning

Allt är gratis och kräver inga kodändringar. Varje steg kan göra nästa
onödigt.

1. **Städa och mät utgångsläget.** Instruktionen står i
   `docs/INSTALLATION.md`.

   ```bash
   pgrep -fl whisper-server      # ska vara tomt när appen inte kör
   sysctl vm.swapusage
   ollama ps                     # vad ligger laddat, och hur stort
   ```

2. **En modell för både chatt och insikter.** Sätt insiktsmodellen till
   qwen3.5:4b under ⌘, och mät minnet under ett provmöte med
   `scripts/mat-belastning.sh`. Försvinner växlingen är hårdvarufrågan
   besvarad här.

3. **MLX inuti Ollama.** Uppgradera, hämta MLX-varianten och jämför mot
   samma möte som gav 592 s.

   ```bash
   ollama --version              # minst 0.34.0
   ollama pull qwen3.5:4b-mlx
   Kundkoll --prov-chatt lokal qwen3.5:4b-mlx
   KUNDKOLL_MODELL=qwen3.5:4b-mlx KUNDKOLL_TORRT=1 Kundkoll --sammanfatta <mötet>
   Kundkoll --prov-insikter qwen3:4b qwen3.5:4b qwen3.5:4b-mlx
   grep -i mlx ~/.ollama/logs/server.log | tail
   ```

   Insiktsprovet är det viktiga: det visar om schema och avstängt tänkande
   håller på MLX-motorn och om medianen blir bättre eller sämre.
   Kvantiseringen är en annan än Q4_K_M, så facit måste köras om oavsett
   hastighet.

4. **LM Studio bara om steg 3 gör besviken**, och då som ett kodarbete på
   ungefär en dag: JSON-schema via `response_format`, inbäddning via
   `/v1/embeddings`, modellista via `/v1/models`, plus en lösning på
   tänkandet.

## Om köpet

Siffrorna pekar på att det är gigabyte minne som avgör, inte chipgeneration.
Räcker steg 2 kan köpet vänta. Ska en 9b-modell köras under pågående möte
med Teams och whisper är det 24 eller 32 GB som köper den friheten, och
MLX:s 20 till 40 procent ändrar inte det.

## Källor

- Ollama v0.19.0, MLX i förhandsversion: https://github.com/ollama/ollama/releases/tag/v0.19.0
- Ollamas releaser till och med v0.34.0: https://github.com/ollama/ollama/releases
- Strukturerad utdata i MLX-runnern (PR #17929): https://github.com/ollama/ollama/pull/17929
- MLX ignorerade `format` (#16563, #17013): https://github.com/ollama/ollama/issues/16563
- `think=false` bröt `format` för gemma4 och qwen3.5 (#15260): https://github.com/ollama/ollama/issues/15260
- qwen3.5:4b-mlx: https://ollama.com/library/qwen3.5:4b-mlx
- LM Studio: enableThinking=false ignoreras för Qwen3.5 (#1990): https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/1990
- LM Studio: strukturerad utdata på llama.cpp och MLX: https://github.com/lmstudio-ai/docs/blob/main/1_developer/3_openai-compat/structured-output.md
- mlx-lm SERVER.md: https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md
- MLX mot Ollama, 15 till 30 procent: https://willitrunai.com/blog/mlx-vs-ollama-apple-silicon-benchmarks
