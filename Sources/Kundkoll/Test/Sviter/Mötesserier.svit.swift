import Foundation

extension Tester {
    static func mötesserier() {
        Prov.svit("Mötesserier")

        Prov.lika(Mötesserie.nyckel("magnus 1on1 20260901"), "magnus on",
                  "siffror och datum plockas bort ur nyckeln")
        Prov.lika(Mötesserie.nyckel("Magnus 1on1 20261001"), "magnus on",
                  "så att nästa möte i serien får samma")
        Prov.lika(Mötesserie.nyckel("Avstämning – vecka 36"), "avstämning vecka",
                  "skiljetecken spelar ingen roll")
        Prov.lika(Mötesserie.nyckel("20260901"), "", "bara siffror ger ingen nyckel")

        func möte(_ titel: String, _ dag: String) -> (Inspelning, URL) {
            (Inspelning(titel: titel, inledd: Uppgift.dag(dag)!, längd: 60, kund: "Acme",
                        projekt: nil, mikrofon: nil, liveYttranden: [], arkivYttranden: nil),
             URL(fileURLWithPath: "/x/\(titel)"))
        }
        let a = möte("magnus 1on1 20260801", "2026-08-01")
        let b = möte("magnus 1on1 20260901", "2026-09-01")
        let c = möte("Styrgrupp", "2026-08-15")
        let d = möte("magnus 1on1 20260701", "2026-07-01")
        let alla = [a, b, c, d]

        Prov.lika(Mötesserie.föregående(b.0, bland: alla)?.0.id, a.0.id,
                  "närmast föregående i serien hittas")
        Prov.lika(Mötesserie.föregående(a.0, bland: alla)?.0.id, d.0.id,
                  "och kedjan fortsätter bakåt")
        Prov.lika(Mötesserie.föregående(d.0, bland: alla)?.0.id, nil,
                  "det första mötet har inget före sig")
        Prov.lika(Mötesserie.föregående(c.0, bland: alla)?.0.id, nil,
                  "ett möte utanför serien hör inte hit")

        let siffror = möte("20260901", "2026-09-01")
        Prov.lika(Mötesserie.föregående(siffror.0, bland: alla + [möte("20260801", "2026-08-01")])?.0.id,
                  nil, "titlar av bara siffror kedjas aldrig")
    }
}
