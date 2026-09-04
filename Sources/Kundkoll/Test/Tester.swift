import Foundation

/// Provsviten. Varje svit bor i en egen fil under Test/Sviter (Namn.svit.swift) och listan
/// här står i samma ordning som filerna: en ny svit läggs till på båda
/// ställena, och proven körs i bokstavsordning så ingen svit kan luta sig
/// mot vad en annan råkade lämna efter sig.
@MainActor
enum Tester {

    static func kör() -> Int32 {
        anteckningar()
        anteckningarMedObsidian()
        arbetscentret()
        arkivet()
        betydelse()
        briefing()
        diagnos()
        förslag()
        indexetFöljerFilerna()
        inspelningensFelvägar()
        kontaktOchRöstprofil()
        kontaktbilder()
        kontakterOchKalender()
        kontaktimport()
        kunskapsbanken()
        lagring()
        liveinsikter()
        ljud()
        lägesbilden()
        mail()
        minVecka()
        modellvalOchMolnspärr()
        möteskopplingar()
        mötesserier()
        mötesuppgifter()
        namnbyte()
        obsidian()
        omindexering()
        palett()
        riktning()
        röster()
        ström()
        tavlanRäknarRätt()
        tid()
        transkriberingsmotorer()
        uppföljning()
        uppgiftsrundor()
        whisper()
        return Prov.sammanfatta()
    }

    /// Ett tomt arkiv i en tillfällig mapp. Den som anropar städar bort mappen.
    static func tillfälligt() -> (Arkivet, URL) {
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        return (Arkivet(rot: rot), rot)
    }
}
