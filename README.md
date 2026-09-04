# Kundkoll

Nativ macOS-app för att hålla ordning på mötes- och telefontranskriberingar
per kund och projekt. Allt ljud och all transkribering sker lokalt på datorn.

## Ursprung

Det här är en fork av Kundkoll av Anders Bjarby (FLTman), anpassad för
Criterio. Grundidén, mätningarna i `docs/` och nästan all kod är hans — se
`LICENSE` (MIT). Vill du stödja ursprungsprojektet finns
[![Patreon](https://img.shields.io/badge/Patreon-st%C3%B6d%20ursprunget-f96854?logo=patreon&logoColor=white)](https://www.patreon.com/AndersBjarby).

Kom igång: `docs/INSTALLATION.md` går igenom allt som behövs utanför appen,
och `scripts/installera.sh` gör det mesta av det åt dig.

## Läge

Alla fyra etapper är klara.

| Etapp | Innehåll | Läge |
|---|---|---|
| 1 | Inspelning av vald mikrofon + datorljud, live-transkript på svenska, mappstruktur med Obsidian-vault per kund | klar |
| – | Röstanalys som delar upp motpartsspåret och känner igen vem som talar | klar |
| 2 | Kontakter, kalender och mejl kopplat till rätt kund | klar |
| 3 | Kunskapsbank och chatt per kund och projekt | klar |
| 4 | Insikter under samtal — fångar frågeställningar och svarar ur kunskapsbanken | klar |

## Layout

Kunder och deras projekt ligger som träd i sidopanelen. Innehållet har flikar —
översikt, inspelningar, anteckningar, mejl — i stället för en lång rulle.
Chatten är en panel som fälls ut till höger och följer det som är valt.

Inspelningen har ett **eget fönster**, som går att lägga bredvid Teams eller på
en andra skärm. Under tiden fungerar resten av appen som vanligt: slå upp vad
som sades förra gången, skriv en anteckning, fråga chatten. En rad längst ned i
huvudfönstret visar att inspelningen pågår och kan stoppa den.

Startas inspelningen från ett kalendermöte börjar den direkt — titel och
deltagare finns i mötet, och mikrofonen är den som användes sist.

## Så fungerar inspelningen

Mikrofonen och datorljudet fångas som **två skilda spår** i samma ström
(ScreenCaptureKit). Att de är åtskilda ger "vem sa vad" utan diarisering: ditt
spår är du, det andra är motparten.

Ljudet delas i fönster vid naturliga pauser i talet och skickas till KB-Whisper
(Kungliga bibliotekets svenska modell) medan samtalet pågår. Vilken lokal
modell liven använder väljs under ⌘,. Fönster utan tal
skickas aldrig iväg: whisper hittar annars på text ur tystnad — se avsnittet i
`docs/VERIFIERAD-STACK.md`. Efter samtalet går
en större modell igenom hela ljudet en gång till och ersätter live-transkriptet
med arkivkvalitet.

Färdiga inspelningar går också att lägga till: en mp4 från Teams eller Zoom, en
m4a från telefonen, en wav från diktafonen. Släpp filen på kunden eller använd
knappen i verktygsraden. Där finns ingen kanaluppdelning, så röstanalysen får
dela upp talarna — och en av dem kan vara du.

Sitter flera personer i mötet delas motpartsspåret upp per röst med pyannote,
och personer kunden är känd för sedan tidigare känns igen automatiskt via
röstavtryck. Vet du antalet röster kan du ange det i «Vem är vem» — det ger
märkbart bättre uppdelning. Osäkra röster lämnas
namnlösa hellre än att gissa fel.

Språket väljs per möte och import: svenska, engelska eller låt motorn avgöra.
KB-Whisper är svensktrimmad och översätter engelska till svenska — uppmätt
även med språket satt till engelska — så engelska möten tar automatiskt vägen
via MLX eller den valda molnmotorn, och ett redan feltranskriberat möte går
att transkribera om från mötesvyn.

Arkivpasset — genomlyssningen efter mötet — har fyra valbara motorer:
whisper.cpp (standard, bäst svenska i mätningen), whisper via Apples MLX,
Whisper hos OpenAI och Scribe hos ElevenLabs. De lokala lämnar aldrig datorn;
molnen skickar ljudet och säger det i klartext i inställningarna. Alla fyra
är uppmätta på samma inspelning — tabellen står i `docs/VERIFIERAD-STACK.md`.

Se `docs/VERIFIERAD-STACK.md` och `docs/RÖSTANALYS.md` för mätningarna bakom
varje val.

## Omvärlden

Kundvyn visar kommande möten, kontakter och mejl som hör till kunden.

**Kalender** (EventKit): ett möte räknas som kundens om någon deltagare finns
bland kundens kontakter, har kundens e-postdomän, eller om kundnamnet står i
titeln. Startas inspelningen från ett möte följer titeln med — och de kallade
blir förslagen när rösterna ska märkas. Reglerna är trubbiga: ett möte de
missar tas i anspråk med «Lägg till möte», och ett de tar fel på skickas bort
med «Hör inte till». Beslutet går före regeln, åt båda hållen.

**Kontakter** (Contacts): personer hämtas ur adressboken eller skrivs upp för
hand, och redigeras i appen — namn, roll, flera adresser och telefonnummer. En
kontakt som skrivits upp för hand kan läggas upp i macOS Kontakter, och ändringar
skrivas tillbaka dit. Det sker bara på knapptryck: adressboken är din egen och
delas med telefonen, så appen ändrar inget där i bakgrunden. En person du satt
namn på i ett transkript läggs upp som kontakt automatiskt. Många på en gång
kommer in via fil: «Importera fil …» i kontaktfönstret läser vCard (dra
personerna från Outlook till Finder) och CSV (Outlook på webben, engelska
eller svenska rubriker). Samma person som redan finns slås ihop på e-post
eller namn, aldrig dubbelt.

**Mail** (AppleScript): söker mejl på kundens adresser, öppnar dem i Mail.
Adresserna är kontakternas, i den ordning de står och högst tolv — utan
kontakter med adress är fliken tom, och de du lägger upp först är de som söks.
Vägen är vald efter mätning — mejlen ligger också som filer under
`~/Library/Mail`, vilket är snabbare vid breda sökningar men kräver Full Disk
Access. Eftersom vi alltid söker på bestämda kundadresser räcker AppleScript,
som bara behöver automationsbehörighet.

## Efter mötet

Ett fyrtio minuter långt samtal blir fyra hundra rader transkript. Det man
behöver därifrån är tre saker, och de skrivs automatiskt efter
efterbearbetningen: vad mötet handlade om, vad som beslutades, och vad någon
lovade att göra. Allt hamnar i `Transkript.md`, så det syns i Obsidian.

Att öppna ett möte ger därför inte en vägg av text. Vyn har tre flikar —
sammanfattning, transkript, att göra — och en chattpanel där hela samtalet
ligger som underlag vid sidan av kunskapsbanken. Åtagandena är mötets egna
kort på tavlan, inte en kopia: bockar man av ett här syns det där. Varje
transkriptrad har en spelknapp — transkriptet är whispers ord, ljudet är
facit. En knapp skriver ett uppföljningsmejl som utkast i Mail, och när
efterbearbetningen blir klar i bakgrunden säger en notis till.

Chattens svar strömmar in medan de skrivs, hos alla fem leverantörerna.

## Inför mötet

En kvart före varje kundmatchat möte kommer en notis; klicket öppnar briefen —
förra mötet i samma serie med kärna och obesvarade frågor, tavlans öppna
åtaganden och mejlen sedan sist. Samma sida nås med «Förbered» på mötesraden.
Briefen byggs helt ur det som redan finns: ingen modell, ingen väntan.

Återkommande möten kedjas till **serier** på titeln med siffrorna bortplockade.
Mötesvyn visar «Förra gången», och mötets chatt får förra sammanfattningen som
stående underlag.

## Läget och tiden i ett projekt

Projektöversikten inleds med **Läget just nu** — en lägesbild skriven av
modellen ur mötessammanfattningar, tavlan, mejl och anteckningar, cachead och
omskriven när underlaget ändrats. Bredvid en faktarad som alltid stämmer:
möten, öppna uppgifter, försenade. Bilden sparas som `Läget.md` i
projektmappen och syns i Obsidian.

Projektet har också en **tidslogg**: ett ur att starta och stoppa med en rad
om vad du gör, och fält för att skriva in tid i efterhand («1:30», «1,5»
eller «90»). Går datorn i vila fryser uret vid insomningen; vid uppvaknandet
frågar en notis om tiden ska loggas eller räknas vidare — sovtid smyger
aldrig in i loggen. En smal rad längst ned i fönstret visar uret var du än
är, och loggen skrivs som `Tid.md` med summor per projekt.

## Att göra

Åtaganden hamnar på en tavla med tre spalter, utan att någon skriver in dem.
Mötets sammanfattning bidrar med sina, nya mejl gås igenom när de hämtas, och
en anteckning gås igenom en stund efter att man slutat skriva i den. Samma sak
nämnd i både ett möte och ett mejl blir ett kort, inte två. Vad som redan
gåtts igenom bokförs per kund, så inget mejl går genom modellen två gånger.
Äldre mejl tas inte av sig själva — «Leta åtaganden i alla mejl» i mejlfliken
gör den genomgången på begäran, äldst först, och kan ta några minuter.

Korten dras mellan spalterna och öppnas med ett klick — det mesta är utplockat
av en modell, och en modell formulerar sig inte alltid som man själv skulle ha
gjort. Tavlan skrivs som `Att göra.md` i kundens valv så den syns i Obsidian.

Modellen räknar också ut **riktiga datum**: «före fredag» sagt en onsdag blir
fredagens datum, och det som passerats utan att bli klart rödmarkeras. En
uppgift kan läggas i macOS Påminnelser — envägs: tavlan är sanningen och
påminnelsen en spegel. **Min vecka** i sidopanelen samlar allt öppet hos alla
kunder, försenat först.

## Söka

⇧⌘F söker i allt material hos alla kunder samtidigt — transkript,
sammanfattningar, anteckningar, mejl och bilagor. Träffarna grupperas per kund,
och orden kapas automatiskt så att «leverans» hittar «leveranstiden».

⌘K öppnar paletten: skriv några bokstäver, hoppa till kund, projekt, möte
eller uppgift.

Chatten söker dessutom på **betydelse**: bge-m3 via Ollama bäddar in allt
lokalt, och en hybrid av BM25 och cosinus väger ihop listorna. Uppmätt tog
hybriden 11 av 12 facitfrågor mot 9 för vardera ensam — det ordsökning aldrig
kan ta är svenska frågor mot engelska dokument. Utan Ollama söker appen som
förut; inget lämnar datorn. Mätningen står i `docs/KUNSKAPSBANK.md`.

## Insikter under samtal

Medan ett möte spelas in lyssnar appen efter sådant deltagarna behöver slå upp,
och svarar ur kunskapsbanken. Svaren dyker upp bredvid live-transkriptet.

En lokal modell via Ollama gör bedömningen, så allt som sägs granskas på
datorn — bara de frågeställningar som faktiskt hittas går vidare. Uppmätt på
riktiga möten: qwen3:8b 12 av 12 rätt utan ett enda falskt larm. Se
`docs/INSIKTER.md`.

## Fråga om kunden

Varje kund och projekt har en chatt som svarar ur kundens eget material —
transkript, anteckningar, mejlämnen och kontakter. Svaren hänvisar till vad de
bygger på, och modellen säger ifrån i stället för att gissa när svaret inte
finns i underlaget.

Chatten är uppdelad i samtal. Ett nytt startas med pennan, och menyn i toppen
bläddrar tillbaka till tidigare — ett samtal handlar oftast om en sak, och att
rensa skulle kasta det man kanske vill tillbaka till.

Underlaget är transkript, anteckningar, mejl **med bilagornas innehåll**,
kontakter och tidigare samtal. Tidigare samtal viktas ner: de säger vad modellen
svarade, inte vad som faktiskt hände. Ett svar kan sparas som anteckning direkt ur
chatten.

**Kopplade mappar** finns i två slag, och appen ser själv vilket. En mapp
med dokument — OneDrive-mappen om kunden, ett projektarkiv — läses in i
kunskapsbanken: Word, Excel, PowerPoint, PDF, text och bilder, bara det som
ändrats sedan sist, och det som tagits bort glöms. Mappen kopplas på kunden
eller på ett projekt och rörs aldrig. En mapp med källkod indexeras däremot
inte; den genomsöks av en agent när du ställer frågan, så att svaret bygger på
hur filerna ser ut just nu. Det tar en halv minut, så det svaret dyker upp
asynkront efter det snabba ur kunskapsbanken.

Sökningen är SQLite FTS5 med trunkerade sökord; svenskans böjningar gör att rak
sökning bara träffar i ett fall av fyra. Mätningen står i
`docs/KUNSKAPSBANK.md`.

Modellen väljs under Inställningar (⌘,) och kan köras hos OpenRouter,
Anthropic, OpenAI, Azure eller lokalt (Ollama, LM Studio, MLX). Valet gäller
allt som går till en modell: chatten, sammanfattningen efter möten, åtaganden
ur mejl och anteckningar, lägesbilden och svaren på insikter. Det som sker av
sig självt körs bara på datorn; med ett moln valt stannar automatiken och
säger varför. Det du själv startar får gå till molnet, och «Leta åtaganden i
alla mejl» kan köras via en molnleverantör som har nyckel, med antalet mejl
som lämnar datorn utskrivet i valet. Sammanfattningar och lägesbilder bär
namnet på modellen som skrev dem. Kopplade kodmappar genomsöks av Claude
Code bara när Anthropic är valt, och då står det i chattens statusrad. De lokala servrarna talar alla
OpenAI-formatet; inställningarna har förvalsknappar som fyller i rätt port.
MLX startas med `mlx_lm.server --model mlx-community/…` och är uppmätt genom
hela provsviten — svar, hänvisningar, strömning och ärligt nej. Chatten är det enda i appen som går ut på nätet, och bara
när du ställer en fråga — väljer du en lokal modell lämnar ingenting datorn.
Nyckeln sparas i macOS nyckelring.

## Anteckningar

Kunder och projekt har anteckningar — vanliga markdownfiler i en
`Anteckningar`-mapp, alltså samma filer som Obsidian öppnar. En anteckning kan
innehålla skärmdumpar: knappen öppnar macOS egen områdesväljare, bilden läggs i
en `bilder`-mapp bredvid och länkas med `![[bilder/…]]` så att Obsidian visar
den. Bilder går också att klistra in eller dra och släppa.

## Data

Allt hamnar under `~/Documents/Kunder`, en Obsidian-vault per kund:

```
~/Documents/Kunder/
  Acme AB/
    .obsidian/
    Acme AB.md
    Projekt/
      Nytt lager/
        Nytt lager.md
        Inspelningar/
        Dokument/
        Anteckningar/
    Samtal/
      2026-08-31 0930 Avstämning/
        jag.wav          16 kHz mono, ditt spår
        motpart.wav      16 kHz mono, motpartens spår
        möte.json        metadata, transkript och vem som talar
        Transkript.md    det Obsidian visar, med wikilänkar
    Kontakter/
      kontakter.json     kundens personer
      Anna Svensson.md   en not per person; uppgifterna i frontmatter,
                         brödtexten din egen och skrivs aldrig över
      röstprofiler.json  kända röster hos den här kunden
    Mail/
    Anteckningar/
```

Filsystemet är sanningen — ingen databas. En kund eller ett projekt som skapas
för hand i Finder eller Obsidian dyker upp i appen utan vidare.

## Krav

Steg för steg i `docs/INSTALLATION.md`; `scripts/installera.sh` sätter upp
punkterna två och tre och `scripts/installera.sh --kontrollera` säger vad
som saknas.

- macOS 26 på Apple Silicon
- `~/Projekt/whisper.cpp` byggd, med `kb_whisper_ggml_small.bin`,
  `kb_whisper_ggml_medium.bin` och `ggml-silero-v5.1.2.bin` i `models/`
- Pythonmiljö med torch, speechbrain och pyannote för röstanalysen; som
  standard `~/Projekt/transcriber/venv`
- Behörighet för **Mikrofon** och **Skärminspelning** (den senare krävs för
  datorljudet — ScreenCaptureKit fångar bara ljud här, ingen bild sparas)
- Frivilligt: **Kalender**, **Kontakter** och **Automatisering** för Mail.
  Appen fungerar utan, men då syns inga möten, kontakter eller mejl.

## Se appen

```bash
./scripts/skarmbild.sh            # fångar fönstret
./scripts/skarmbild.sh --starta   # startar om appen först
```

`screencapture -l <fönster-id>` svarar "could not create image from window" när
appen ligger bakom — macOS släpper backing store för dolda fönster, och det ser
ut som ett behörighetsfel utan att vara det. Skriptet lyfter därför fram
fönstret först, gör flera försök, och faller tillbaka på hela skärmen.

## Bygga

```bash
./scripts/bygg-app.sh                                        # dist/Critero-kundkoll.app
.build/arm64-apple-macosx/debug/Kundkoll --test              # provsviten, 704 prov
.build/arm64-apple-macosx/debug/Kundkoll --hjälp             # alla provlägen med argument
.build/arm64-apple-macosx/debug/Kundkoll --prov-ljud f.wav   # hela kedjan skarpt
.build/arm64-apple-macosx/debug/Kundkoll --prov-röst ljud.wav w.json facit.json
.build/arm64-apple-macosx/debug/Kundkoll --prov-chatt [leverantör] [modell]
```

Ett provläge med fel argument skriver hjälpen och slutar med kod 2 i stället
för att tyst starta appen. Xcode behövs inte, Command Line Tools räcker. Har du ett Developer
ID-certifikat anger du det med `KUNDKOLL_SIGNERING`, så signeras appen med
det och macOS kommer ihåg beviljade behörigheter mellan ombyggen. Utan
certifikat signeras appen ad hoc och behörigheterna får ges om vid varje bygge.

## Licens

MIT, se `LICENSE`.
