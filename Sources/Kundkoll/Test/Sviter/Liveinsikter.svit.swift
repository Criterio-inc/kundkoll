import Foundation

extension Tester {
    static func liveinsikter() {
        Prov.svit("Liveinsikter")

        Prov.kolla(!Liveinsikter.dagsAttGranska(tecken: 40, väntat: 3),
                   "en enda mening granskas inte direkt")
        Prov.kolla(Liveinsikter.dagsAttGranska(tecken: 200, väntat: 3),
                   "ett stycke räcker för att granska")
        Prov.kolla(Liveinsikter.dagsAttGranska(tecken: 40, väntat: 30),
                   "i ett långsamt samtal granskas det lilla som sagts ändå")
        Prov.kolla(!Liveinsikter.dagsAttGranska(tecken: 0, väntat: 300),
                   "men tystnad granskas aldrig, hur länge den än varar")
    }
}
