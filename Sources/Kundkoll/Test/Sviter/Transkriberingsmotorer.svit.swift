import Foundation

extension Tester {
    static func transkriberingsmotorer() {
        Prov.svit("Transkriberingsmotorer")

        // mlx_whispers JSON, som den såg ut i den uppmätta körningen.
        let mlx = #"{"language":"sv","text":"x","segments":[{"id":0,"start":0.0,"end":4.0,"text":" Okej, då spelar jag in ett möte."},{"id":1,"start":17.0,"end":21.0,"text":" Jag lyssnar."}]}"#
        let mlxRader = MlxWhisper.tolka(Data(mlx.utf8), röst: .motpart)
        Prov.lika(mlxRader.count, 2, "mlx-segmenten blir yttranden")
        Prov.lika(mlxRader.first?.text, "Okej, då spelar jag in ett möte.",
                  "texten trimmas")
        Prov.lika(mlxRader.first?.slut, 4.0, "tiderna är sekunder rakt av")

        let mlxTomt = #"{"segments":[{"start":0.0,"end":2.0,"text":" Tack."}]}"#
        Prov.lika(MlxWhisper.tolka(Data(mlxTomt.utf8), röst: .motpart).count, 0,
                  "påhittsfraserna filtreras även här")

        // OpenAIs verbose_json.
        let oa = #"{"task":"transcribe","segments":[{"start":0.0,"end":10.0,"text":" Okej, då spelar jag in ett möte."},{"start":30.0,"end":34.0,"text":" Vilka var de 20 uppgifterna?"}]}"#
        let oaRader = Molntranskribering.tolkaOpenAI(Data(oa.utf8), röst: .jag)
        Prov.lika(oaRader.count, 2, "OpenAI-segmenten blir yttranden")
        Prov.lika(oaRader.last?.start, 30.0, "med sina tider")

        // Scribes ord med tider — sys ihop vid pauserna.
        let scribe = #"{"language_code":"swe","text":"x","words":["#
            + #"{"text":"Okej,","start":2.0,"end":2.3,"type":"word"},"#
            + #"{"text":" ","start":2.3,"end":2.4,"type":"spacing"},"#
            + #"{"text":"då","start":2.4,"end":2.6,"type":"word"},"#
            + #"{"text":"(skratt)","start":2.6,"end":3.0,"type":"audio_event"},"#
            + #"{"text":"kör","start":2.7,"end":3.0,"type":"word"},"#
            + #"{"text":"Nästa","start":9.5,"end":9.9,"type":"word"},"#
            + #"{"text":"mening","start":10.0,"end":10.4,"type":"word"}]}"#
        let sc = Molntranskribering.tolkaScribe(Data(scribe.utf8), röst: .motpart)
        Prov.lika(sc.count, 2, "orden sys ihop till yttranden vid pauserna")
        Prov.lika(sc.first?.text, "Okej, då kör", "mellanslag och ljudhändelser hoppas över")
        Prov.lika(sc.first?.start, 2.0, "första ordets start är yttrandets")
        Prov.lika(sc.last?.text, "Nästa mening", "pausen på sex sekunder delar")

        Prov.lika(Molntranskribering.tolkaScribe(Data(#"{"detail":{"message":"fel"}}"#.utf8),
                                                 röst: .jag).count, 0,
                  "ett felsvar ger inga rader")

        // Inställningen överlever gamla filer utan nya fält.
        let gammal = try? JSONDecoder().decode(Transkriberingsval.self,
                                               from: Data(#"{"motor":"openai"}"#.utf8))
        Prov.lika(gammal?.motor, .openai, "sparade val utan alla fält går att läsa")
        Prov.lika(gammal?.arkivmodell, "whisper-1", "och tom modell betyder motorns standard")

        // Loopfiltret: 773 rader «Good afternoon.» i följd hände på riktigt.
        func y(_ t: String) -> Yttrande { Yttrande(röst: .motpart, text: t, start: 0, slut: 1) }
        let loop = [y("Hej")] + Array(repeating: y("Good afternoon."), count: 700) + [y("Slut")]
        let rensad = MlxWhisper.utanUpprepningar(loop)
        Prov.lika(rensad.map(\.text), ["Hej", "Good afternoon.", "Slut"],
                  "en loop kokas ner till sin första rad")
        let äkta = [y("Ja."), y("Ja."), y("Precis.")]
        Prov.lika(MlxWhisper.utanUpprepningar(äkta).count, 3,
                  "korta äkta upprepningar lämnas i fred")

        // Språkvägvalet: KB översätter allt till svenska — uppmätt blev
        // engelskt ljud svenska även med -l en — så andra språk routas bort.
        let kb = Arkivtranskribering.vägval(motor: .whisperCpp,
                                            modell: "kb_whisper_ggml_medium.bin", språk: "sv")
        Prov.lika(kb?.motor, .whisperCpp, "svenska stannar hos KB")
        let eng = Arkivtranskribering.vägval(motor: .whisperCpp,
                                             modell: "kb_whisper_ggml_medium.bin", språk: "en")
        Prov.lika(eng?.motor, .mlx, "engelska med KB-modell tar vägen via MLX")
        let auto = Arkivtranskribering.vägval(motor: .whisperCpp,
                                              modell: "kb_whisper_ggml_medium.bin", språk: nil)
        Prov.lika(auto?.motor, .mlx, "avgör-själv likaså — KB kan inte avgöra")
        let moln = Arkivtranskribering.vägval(motor: .elevenlabs,
                                              modell: "scribe_v2", språk: "en")
        Prov.lika(moln?.motor, .elevenlabs, "molnmotorer rör inte vägvalet")
        let annan = Arkivtranskribering.vägval(motor: .whisperCpp,
                                               modell: "ggml-large-v3.bin", språk: "en")
        Prov.lika(annan?.motor, .whisperCpp,
                  "en whisper.cpp-modell som inte är KB får köra engelska själv")

        Prov.kolla(!Transkriberingsval.lokalaModeller().isEmpty,
                   "modellistan hittar ggml-filerna")
        Prov.kolla(!Transkriberingsval.lokalaModeller().contains { $0.contains("silero") },
                   "men inte taldetektorn")
        Prov.kolla(!Transkriberingsval.lokalaModeller().contains { $0.hasPrefix("for-tests") },
                   "och inte testfixturerna")
    }
}
