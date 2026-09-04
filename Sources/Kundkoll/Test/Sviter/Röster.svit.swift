import Foundation

extension Tester {
    static func röster() {
        Prov.svit("Röstanalys")

        func y(_ start: Double, _ slut: Double, _ text: String = "text") -> Yttrande {
            Yttrande(röst: .motpart, text: text, start: start, slut: slut)
        }

        do {   // turbyggande
            let turer = Röstanalys.turer(av: [
                y(0, 3), y(3.2, 6),          // 0,2 s paus — samma tur
                y(9, 12), y(12.1, 15),       // 3 s paus bryter, sedan ihop igen
            ])
            Prov.lika(turer.count, 2, "korta pauser håller ihop turen, långa bryter")
            Prov.lika(turer.first?.start, 0, "turen börjar vid första yttrandet")
            Prov.lika(turer.first?.slut, 6, "och slutar vid det sista före pausen")
        }

        do {   // för korta turer sållas bort
            let turer = Röstanalys.turer(av: [y(0, 0.8), y(5, 9)])
            Prov.lika(turer.count, 1, "turer under \(Tröskel.minstaTurLängd) s kastas")
            Prov.lika(turer.first?.längd, 4, "den långa blir kvar")
        }

        do {   // taket bryter långa turer
            var rader: [Yttrande] = []
            for i in 0..<20 { rader.append(y(Double(i) * 2, Double(i) * 2 + 1.9)) }
            let turer = Röstanalys.turer(av: rader, tak: 12)
            Prov.kolla(turer.allSatisfy { $0.längd <= 13 },
                       "ingen tur blir längre än taket och hinner blanda in nästa person")
            Prov.kolla(turer.count > 1, "den långa monologen delas upp (\(turer.count) turer)")
        }

        do {   // trösklarna följer längden
            Prov.kolla(Tröskel.samma(sekunder: 2) < Tröskel.samma(sekunder: 10),
                       "kort ljud kräver lägre tröskel än långt")
            Prov.kolla(Tröskel.namnge(sekunder: 5) > Tröskel.samma(sekunder: 5),
                       "att sätta namn kräver mer säkerhet än att bunta ihop")
            Prov.kolla(Tröskel.sammaGrupp(sekunder: 30) > Tröskel.samma(sekunder: 30),
                       "andra rundan är strängare, annars slås lika röster ihop")
        }

        do {   // avtryck och likhet
            let a = Avtryck(vektor: [1, 0, 0], sekunder: 5)
            let b = Avtryck(vektor: [1, 0, 0], sekunder: 5)
            let c = Avtryck(vektor: [0, 1, 0], sekunder: 5)
            Prov.lika(a.likhet(b), 1.0, "identiska avtryck ger likhet 1")
            Prov.lika(a.likhet(c), 0.0, "vinkelräta avtryck ger 0")
            Prov.lika(a.likhet(Avtryck(vektor: [1, 0], sekunder: 5)), 0.0,
                      "olika längd ger 0 i stället för att krascha")
        }

        do {   // profiler
            var p = Röstprofil(namn: "Anna", avtryck: [Avtryck(vektor: [1, 0, 0], sekunder: 5)],
                               uppdaterad: Date(), samtal: 1)
            Prov.lika(p.likhet(Avtryck(vektor: [1, 0, 0], sekunder: 5)), 1.0, "profilen känner igen sig själv")
            p.lärDig(Avtryck(vektor: [0, 1, 0], sekunder: 9))
            Prov.lika(p.avtryck.count, 2, "profilen lär sig nya avtryck")
            Prov.lika(p.likhet(Avtryck(vektor: [0, 1, 0], sekunder: 5)), 1.0,
                      "bästa träffen räknas, inte medelvärdet")
            for i in 0..<12 { p.lärDig(Avtryck(vektor: [0, 0, 1], sekunder: Double(i))) }
            Prov.kolla(p.avtryck.count <= 8, "profilen växer inte i all oändlighet (\(p.avtryck.count))")
            Prov.kolla(p.avtryck.contains { $0.sekunder == 9 }, "de längsta avtrycken behålls vid gallring")
        }

        do {   // gruppering
            func a(_ v: [Float], _ s: Double) -> Avtryck { Avtryck(vektor: v, sekunder: s) }
            let t1 = Röstanalys.Tur(start: 0, slut: 8, text: "en")
            let t2 = Röstanalys.Tur(start: 10, slut: 18, text: "två")
            let t3 = Röstanalys.Tur(start: 20, slut: 28, text: "tre")
            // Två nästan identiska röster och en helt annan
            let nära1: [Float] = [1, 0, 0]
            let nära2: [Float] = [0.99, 0.14, 0]
            let annan: [Float] = [0, 0, 1]
            let grupper = Röstanalys.gruppera([(t1, a(nära1, 8)), (t2, a(nära2, 8)), (t3, a(annan, 8))])
            Prov.lika(grupper.count, 2, "lika röster buntas ihop, olika hålls isär")
            Prov.kolla(grupper.first?.turer.count == 2, "den största gruppen har de två lika")
        }

        do {   // var kedjan klipps
            // Likheten faller monotont när grupper slås ihop. Det största
            // fallet är övergången från samma person till olika.
            //            5      4      3      2      1
            let kedja = [0.82, 0.78, 0.73, 0.40, -Double.infinity]
            Prov.lika(Röstanalys.klippställe(kedja), 3,
                      "klipper där likheten faller mest")

            // Ett jämnt fall utan tydlig gräns
            Prov.kolla(Röstanalys.klippställe([0.8, 0.7, 0.6, 0.5, -Double.infinity]) >= 0,
                       "en jämn kedja ger ändå ett svar")
            Prov.lika(Röstanalys.klippställe([0.5]), 0, "en kedja med ett läge klipps först")
            Prov.lika(Röstanalys.klippställe([]), 0, "tom kedja kraschar inte")
        }

        do {   // långa turer blir kärnor
            func p(_ längd: Double, _ v: [Float]) -> (Röstanalys.Tur, Avtryck) {
                (Röstanalys.Tur(start: 0, slut: längd, text: ""),
                 Avtryck(vektor: v, sekunder: längd))
            }
            let (kärnor, korta) = Röstanalys.delaEfterLängd([
                p(20, [1, 0, 0]), p(18, [0, 1, 0]),      // långa
                p(2, [1, 0, 0]), p(3, [0, 1, 0]), p(2.5, [1, 0, 0]),   // korta
            ])
            Prov.kolla(kärnor.allSatisfy { $0.0.längd >= Tröskel.minstaKärnlängd },
                       "bara långa turer blir kärnor")
            Prov.kolla(korta.allSatisfy { $0.0.längd < 20 }, "de korta hamnar i resten")
            Prov.kolla(kärnor.count >= 1 && korta.count >= 3,
                       "uppdelningen ger både kärnor och rester (\(kärnor.count)/\(korta.count))")
        }

        do {   // korta turer hamnar hos rätt röst i stället för att bli egna
            func p(_ start: Double, _ längd: Double, _ v: [Float]) -> (Röstanalys.Tur, Avtryck) {
                (Röstanalys.Tur(start: start, slut: start + längd, text: ""),
                 Avtryck(vektor: v, sekunder: längd))
            }
            let a: [Float] = [1, 0, 0]
            let b: [Float] = [0, 1, 0]
            // Två tydliga röster i långa turer, plus fem korta inpass
            let grupper = Röstanalys.gruppera([
                p(0, 20, a), p(30, 18, b), p(60, 16, a), p(90, 15, b),
                p(120, 2, a), p(125, 3, b), p(130, 2, a), p(135, 2.5, b), p(140, 2, a),
            ], väntade: 2)
            Prov.lika(grupper.count, 2,
                      "korta inpass blir inte egna röster (\(grupper.count) grupper)")
            Prov.lika(grupper.reduce(0) { $0 + $1.turer.count }, 9,
                      "alla turer kommer med någonstans")
        }

        do {   // väntat antal styr
            func p(_ v: [Float]) -> (Röstanalys.Tur, Avtryck) {
                (Röstanalys.Tur(start: 0, slut: 12, text: ""), Avtryck(vektor: v, sekunder: 12))
            }
            let par = [p([1, 0, 0]), p([0.98, 0.2, 0]), p([0, 1, 0]), p([0, 0.98, 0.2]),
                       p([0, 0, 1]), p([0.2, 0, 0.98])]
            Prov.kolla(Röstanalys.gruppera(par, väntade: 3).count <= 3,
                       "ett väntat antal ger inte fler röster än så")
            Prov.kolla(Röstanalys.gruppera(par, väntade: 2).count <= 2,
                       "och håller ihop hårdare när färre väntas")
        }

        do {   // namngivning kräver säkerhet
            let t = Röstanalys.Tur(start: 0, slut: 10, text: "hej")
            let grupper = Röstanalys.gruppera([(t, Avtryck(vektor: [1, 0, 0], sekunder: 10))])
            let profil = Röstprofil(namn: "Anna", avtryck: [Avtryck(vektor: [1, 0, 0], sekunder: 10)],
                                    uppdaterad: Date(), samtal: 1)
            Prov.lika(Röstanalys.namnge(grupper, mot: [profil]).first?.namn, "Anna",
                      "en säker träff får namnet")

            let svag = Röstprofil(namn: "Berit", avtryck: [Avtryck(vektor: [0.5, 0.86, 0], sekunder: 10)],
                                  uppdaterad: Date(), samtal: 1)
            Prov.kolla(Röstanalys.namnge(grupper, mot: [svag]).first?.namn == nil,
                       "en osäker träff lämnas namnlös hellre än att gissa fel")
        }

        do {   // två grupper får inte samma namn
            let t1 = Röstanalys.Tur(start: 0, slut: 10, text: "en")
            let t2 = Röstanalys.Tur(start: 30, slut: 40, text: "två")
            let g = [Röstanalys.Röstgrupp(turer: [t1], avtryck: [Avtryck(vektor: [1, 0, 0], sekunder: 10)]),
                     Röstanalys.Röstgrupp(turer: [t2], avtryck: [Avtryck(vektor: [0.97, 0.24, 0], sekunder: 10)])]
            let profil = Röstprofil(namn: "Anna", avtryck: [Avtryck(vektor: [1, 0, 0], sekunder: 10)],
                                    uppdaterad: Date(), samtal: 1)
            let ut = Röstanalys.namnge(g, mot: [profil])
            Prov.lika(ut.filter { $0.namn == "Anna" }.count, 1,
                      "samma person sätts bara på en grupp")
        }

        do {   // tilldelning enligt diarisering
            func t(_ start: Double, _ slut: Double) -> Röstanalys.Tur {
                Röstanalys.Tur(start: start, slut: slut, text: "")
            }
            let turer = [t(0, 10), t(12, 20), t(25, 35), t(40, 45)]
            let segment = [
                Röstanalys.Talarsegment(start: 0, slut: 11, talare: "A"),
                Röstanalys.Talarsegment(start: 11, slut: 22, talare: "B"),
                Röstanalys.Talarsegment(start: 22, slut: 36, talare: "A"),
                Röstanalys.Talarsegment(start: 36, slut: 50, talare: "B"),
            ]
            let grupper = Röstanalys.gruppera(turer: turer, avtryck: [:], enligt: segment)
            Prov.lika(grupper.count, 2, "två talare ger två grupper")
            // A talar 0–10 och 25–35, alltså 20 s; B talar 12–20 och 40–45, 13 s
            Prov.lika(grupper.first?.turer.count, 2, "största gruppen har sina två turer")
            Prov.kolla(grupper.allSatisfy { $0.turer.count == 2 },
                       "turerna fördelas efter var de överlappar mest")

            // En tur som spänner över en talarväxling hamnar hos den som har mest
            let delad = Röstanalys.gruppera(
                turer: [t(8, 16)], avtryck: [:], enligt: segment)
            Prov.lika(delad.count, 1, "en tur hamnar hos en enda talare")
            Prov.lika(delad.first?.turer.count, 1, "och tas inte bort")

            Prov.lika(Röstanalys.gruppera(turer: turer, avtryck: [:], enligt: []).count, 0,
                      "utan segment blir det inga grupper")
        }

        do {   // etiketter och lagring
            var y1 = Yttrande(röst: .motpart, text: "hej", start: 0, slut: 2)
            y1.röstgrupp = 0
            Prov.lika(y1.etikett([:]), "Röst 1", "namnlös grupp visas med nummer")
            Prov.lika(y1.etikett([0: "Anna"]), "Anna", "namngiven grupp visar namnet")
            let mitt = Yttrande(röst: .jag, text: "hej", start: 0, slut: 2)
            Prov.lika(mitt.etikett([0: "Anna"]), "Jag", "mitt eget spår är alltid jag")
        }

        do {   // profiler sparas per kund
            // Delningen är en inställning i appens UserDefaults; provet ska
            // inte bero på vad Pär råkar ha valt (föll i dist-binären, som
            // ser appens riktiga inställningar).
            let delade = Inställningar.delaRöstprofiler
            Inställningar.delaRöstprofiler = false
            defer { Inställningar.delaRöstprofiler = delade }
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let a = try! arkiv.skapaKund(namn: "Acme")
            let b = try! arkiv.skapaKund(namn: "Beta")
            try! arkiv.lärDigRöst(namn: "Anna", avtryck: Avtryck(vektor: [1, 0, 0], sekunder: 6), hos: a)
            Prov.lika(arkiv.röstprofiler(för: a).count, 1, "profilen sparas hos kunden")
            Prov.lika(arkiv.röstprofiler(för: b).count, 0, "och läcker inte till andra kunder")
            try! arkiv.lärDigRöst(namn: "Anna", avtryck: Avtryck(vektor: [0, 1, 0], sekunder: 7), hos: a)
            let p = arkiv.röstprofiler(för: a).first
            Prov.lika(p?.avtryck.count, 2, "ett andra samtal lägger till ett avtryck")
            Prov.lika(p?.samtal, 2, "antalet samtal räknas upp")
        }
    }
}
