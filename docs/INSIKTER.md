# Insikter under samtal

Medan ett möte spelas in lyssnar appen efter sådant deltagarna behöver slå upp,
och svarar ur kunskapsbanken. Svaren dyker upp bredvid live-transkriptet.

Bara det deltagarna själva undrar över visas — inga sammanfattningar, inga
förslag. En assistent som talar oombedd under ett möte blir avstängd.

## Kedjan

```
transkriptrad → buffert (~180 tecken) → lokal modell: behöver detta slås upp?
                                              ↓ ja
                                     kunskapsbanken (FTS5)
                                              ↓
                                     chattens modell → svar i panelen
```

Ordningen spelar roll för integriteten. **Allt som sägs granskas lokalt.** Bara
de frågeställningar som faktiskt hittas går vidare — och bara till den modell
som valts för chatten. Är den satt till en lokal modell lämnar ingenting
datorn.

## Vilken modell som lyssnar

Uppmätt på tolv stycken ur riktiga möten, med facit:

| Modell | Rätt | Falska larm | Median |
|---|---|---|---|
| Apple FoundationModels | 3/8 | många | 0,6 s |
| gemma3:1b | 7/12 | 4 | 0,8 s |
| gemma3:4b | 11/12 | 1 | 1,7 s |
| **qwen3:8b** | **12/12** | **0** | **1,4 s** |

Falska larm väger tyngst. En assistent som avbryter mötet med påhittade frågor
blir avstängd; en som missar en fråga stör ingen.

### Apples inbyggda modell dög inte

Den var det ursprungliga valet — snabb, gratis, helt lokal. Men den träffade
3 av 8 och hittade frågeställningar där det inte fanns några. En liten modell
som ombeds skriva fritt vill alltid vara hjälpsam:

```
«Det ska vara spontant nog att kännas fritt, men planerat nog att folk dyker upp.»
→ "Finns det specifika exempel på möten där ni diskuterat miljö för mötet?"
```

Apples `@Generable`, som hade gjort det till en ren klassificering i stället för
fritext, kräver ett makro-plugin som bara finns i Xcode-toolchainen — inte i
Command Line Tools, som appen byggs med.

Ollama tar däremot emot ett JSON-schema och håller sig till det. Med `format`
satt till ett schema med ett booleskt fält blir uppgiften en klassificering, och
då slutar modellen leta efter något att säga.

## Detaljer som betyder något

**`"think": false`** — utan det lägger qwen3 tid på att tänka högt inför en
ja-eller-nej-fråga.

**Buffert på ~180 tecken, som mest 25 sekunder.** Ett par meningar räcker sällan
för att avgöra om något behöver slås upp, men ett långsamt samtal ska ändå få
sina insikter.

**En granskning i taget.** Samtalet fortsätter medan modellen tänker, och
överlappande granskningar skulle ge dubbla insikter.

**Samma fråga två gånger filtreras bort** genom ordöverlapp: samma sak kommer
ofta upp flera gånger under ett möte.

## Köra provet

```bash
Kundkoll --prov-insikter                        # den valda modellen
Kundkoll --prov-insikter qwen3:8b gemma3:4b     # jämför flera
```

Provet kräver att Ollama är igång (`ollama serve`).
