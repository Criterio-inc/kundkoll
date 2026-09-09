import Foundation

extension Tester {
    static func diktat() {
        Prov.svit("Reflektioner på hemvägen")
        let (arkiv, rot) = tillfälligt()
        defer { try? FileManager.default.removeItem(at: rot) }
        let borås = try! arkiv.skapaKund(namn: "Borås stad")
        _ = try! arkiv.skapaKund(namn: "Landskrona kommun")
        let kunder = arkiv.kunder.map(\.namn)

        do {   // modellens delar
            let svar = #"{"delar":[{"kund":"borås stad","text":"Mötet med Erik gick bra."},{"kund":"Halmstad","text":"Ringde Halmstad."},{"kund":null,"text":"Trött i dag."},{"kund":"Landskrona kommun","text":""}]}"#
            let delar = Diktat.tolka(svar, kunder: kunder)!
            Prov.lika(delar.count, 3, "tomma delar faller bort")
            Prov.lika(delar[0].kund, "Borås stad", "kundnamnet känns igen oavsett versaler och får rätt stavning")
            Prov.lika(delar[1].kund, nil, "en kund som inte finns blir ingen kund, texten behålls")
            Prov.lika(delar[2].kund, nil, "null är ingen kund")
            Prov.lika(Diktat.tolka("Jag kan inte dela upp det här.", kunder: kunder), nil, "prosa i stället för JSON ger nil")
            let bild = [Diktat.Kundbild(namn: "Borås stad", projekt: ["Informationshantering i M365"], personer: ["Maria Rangefil"]),
                        Diktat.Kundbild(namn: "Landskrona kommun")]
            let u = Diktat.uppdrag(text: "x", kunder: bild)
            Prov.kolla(u.contains("«Borås stad»: uppdraget «Informationshantering i M365». Personer: Maria Rangefil")
                       && u.contains("- «Landskrona kommun»") && u.contains("en enda kund"),
                       "modellen får uppdrag och personer per kund, och regeln om en kund")
            Prov.kolla(Diktat.uppdrag(text: "x", kunder: kunder).contains("«Borås stad»") && Diktat.uppdrag(text: "x", kunder: kunder).contains("«Landskrona kommun»"),
                       "prompten räknar upp kunderna")
        }

        do {   // nya filer: bara sådana som stått stilla ett varv och inte är klara
            let mapp = rot.appending(path: "Diktat")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            let a = mapp.appending(path: "Ny inspelning 3.m4a")
            try! Data(repeating: 1, count: 1000).write(to: a)
            try! Data("x".utf8).write(to: mapp.appending(path: "läs mig.txt"))
            var sedda: [String: Int] = [:]
            Prov.kolla(Diktat.nya(i: mapp, klara: [:], senastSedda: &sedda).isEmpty, "första varvet ses filen bara")
            try! Data(repeating: 1, count: 2000).write(to: a)
            Prov.kolla(Diktat.nya(i: mapp, klara: [:], senastSedda: &sedda).isEmpty, "en fil som växer väntar")
            Prov.lika(Diktat.nya(i: mapp, klara: [:], senastSedda: &sedda).map(\.lastPathComponent), ["Ny inspelning 3.m4a"],
                      "stilla ett varv: nu tas den, och textfilen räknas inte")
            Prov.kolla(Diktat.nya(i: mapp, klara: ["Ny inspelning 3.m4a": 2000], senastSedda: &sedda).isEmpty,
                       "en bokförd fil tas inte igen")
        }

        do {   // sparas som Reflektion <dag>, och fylls på samma dag
            let dag = Uppgift.dag("2026-09-07")!.addingTimeInterval(17 * 3600 + 20 * 60)
            let a = try! Diktat.spara("Mötet med Erik gick bra.", i: borås.anteckningsmapp, dag: dag, arkiv: arkiv)
            Prov.lika(a.titel, "Reflektion 7 sep", "rubriken är dagen, utan punkt som skulle gett «sep..md»")
            Prov.kolla(a.text.hasPrefix("# Reflektion 7 sep") && a.text.contains("Mötet med Erik gick bra."), "texten står i noten")
            let b = try! Diktat.spara("Glömde fråga om budgeten.", i: borås.anteckningsmapp, dag: dag.addingTimeInterval(3600), arkiv: arkiv)
            Prov.lika(b.fil, a.fil, "ett andra diktat samma dag går in i samma not")
            Prov.kolla(b.text.contains("Mötet med Erik") && b.text.contains("## 18:20") && b.text.contains("Glömde fråga"),
                       "med en tidsrubrik före det nya")
            Prov.lika(arkiv.anteckningar(i: borås.anteckningsmapp).count, 1, "en anteckning hos kunden")
            let kundsida = (try? String(contentsOf: borås.mapp.appending(path: "Borås stad.md"), encoding: .utf8)) ?? ""
            Prov.kolla(kundsida.contains("Reflektion 7 sep"), "och kundsidan i Obsidian länkar till den")
            Prov.lika(Diktat.anteckningsmapp(för: borås, arkiv: arkiv), borås.anteckningsmapp, "utan projekt sparas hos kunden")
            let uppdrag = try! arkiv.skapaProjekt(namn: "M365", hos: borås)
            Prov.lika(Diktat.anteckningsmapp(för: borås, arkiv: arkiv).resolvingSymlinksInPath().path,
                      uppdrag.anteckningsmapp.resolvingSymlinksInPath().path, "med ett enda projekt sparas i projektet")
            let brief = Briefing.bygg(för: borås, möte: nil, arkiv: arkiv)
            Prov.lika(brief.reflektion?.titel, "Reflektion 7 sep", "briefen tar med senaste reflektionen")
        }
    }
}
