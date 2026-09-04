import Foundation

extension Tester {
    static func anteckningar() {
        Prov.svit("Anteckningar")
        let fm = FileManager.default

        do {
            let rot = fm.temporaryDirectory.appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
            let mapp = projekt.anteckningsmapp

            let a = try! arkiv.nyAnteckning(i: mapp, titel: "Möte om layout")
            Prov.kolla(fm.fileExists(atPath: a.fil.path), "anteckningen blir en markdownfil")
            Prov.lika(a.fil.pathExtension, "md", "med rätt filändelse")
            Prov.lika(arkiv.anteckningar(i: mapp).count, 1, "och hittas i mappen")

            // Samma rubrik två gånger ska inte skriva över
            let b = try! arkiv.nyAnteckning(i: mapp, titel: "Möte om layout")
            Prov.kolla(a.fil != b.fil, "samma rubrik ger inte samma fil")
            Prov.lika(arkiv.anteckningar(i: mapp).count, 2, "båda finns kvar")

            var c = a
            c.text = "# Möte om layout\n\nLagret ska rymma 400 pallplatser.\n"
            try! arkiv.spara(c)
            let läst = arkiv.anteckningar(i: mapp).first { $0.titel == a.titel }
            Prov.kolla(läst?.text.contains("400 pallplatser") == true, "texten sparas")
            Prov.lika(läst?.utdrag, "Lagret ska rymma 400 pallplatser.",
                      "utdraget hoppar över rubriken")

            let omdöpt = try! arkiv.döpOm(c, till: "Layoutmöte 12 sep")
            Prov.lika(omdöpt.titel, "Layoutmöte 12 sep", "anteckningen går att döpa om")
            Prov.kolla(!fm.fileExists(atPath: a.fil.path), "den gamla filen lämnas inte kvar")
            Prov.kolla(fm.fileExists(atPath: omdöpt.fil.path), "den nya filen finns")

            try! arkiv.taBort(omdöpt)
            Prov.lika(arkiv.anteckningar(i: mapp).count, 1, "anteckningar går att ta bort")
        }

        do {   // bilder
            let rot = fm.temporaryDirectory.appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let mapp = kund.anteckningsmapp

            let namn = try! arkiv.sparaBild(Data([0x89, 0x50, 0x4E, 0x47]), ändelse: "png", i: mapp)
            Prov.kolla(namn.hasPrefix("bilder/"), "bilden hamnar i en egen mapp (\(namn))")
            Prov.kolla(fm.fileExists(atPath: mapp.appending(path: namn).path),
                       "filen finns på disk")

            var a = try! arkiv.nyAnteckning(i: mapp, titel: "Skisser")
            a.text = "# Skisser\n\n![[\(namn)]]\n\nText emellan\n\n![[bilder/annan.png]]\n"
            Prov.lika(a.bilder.count, 2, "båda bilderna hittas i texten")
            Prov.lika(a.bilder.first, namn, "i den ordning de förekommer")

            a.text = "# Utan bilder\n\nSe [[En annan anteckning]] för mer.\n"
            Prov.lika(a.bilder.count, 0,
                      "vanliga wikilänkar räknas inte som bilder")
        }

        do {   // filnamn
            let rot = fm.temporaryDirectory.appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let a = try! arkiv.nyAnteckning(i: kund.anteckningsmapp, titel: "Före/efter: ändringar")
            Prov.kolla(!a.titel.contains("/"),
                       "snedstreck i rubriken skapar inte oavsiktliga undermappar")
            Prov.kolla(fm.fileExists(atPath: a.fil.path), "anteckningen skapas ändå")

            let tom = try! arkiv.nyAnteckning(i: kund.anteckningsmapp, titel: "")
            Prov.lika(tom.titel, "Anteckning", "en anteckning utan rubrik får ett namn ändå")
        }
    }
}
