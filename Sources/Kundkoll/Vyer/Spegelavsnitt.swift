import SwiftUI
import AppKit

/// «Spegel till Cowork» på projektets översikt: mappen ett Cowork-projekt
/// läser, dit Kundkoll skriver lägesbilden, tavlan, mötena och anteckningarna.
struct Spegelavsnitt: View {
    let kund: Kund
    let projekt: Projekt

    @EnvironmentObject private var arkiv: Arkivet
    @State private var mapp: URL?
    @State private var besked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Spegel till Cowork")
                Spacer()
                if mapp != nil {
                    Button("Skriv nu", action: skriv).buttonStyle(.link)
                    Button("Koppla bort", action: kopplaBort).buttonStyle(.link)
                }
                Button(mapp == nil ? "Välj mapp" : "Byt mapp", action: välj).buttonStyle(.link)
            }
            if let mapp {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Stil.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(förkorta(mapp.path))
                            .font(.callout)
                        Text("Lägesbilden, tavlan, mötenas sammanfattningar och anteckningarna skrivs hit och skrivs om när de ändras. Kundkoll äger mappen, så ändra inte i den. Transkript, ljud och mejl stannar på datorn.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !FileManager.default.fileExists(atPath: mapp.path) {
                            Text("Mappen finns inte just nu. Är det en molnmapp skrivs spegeln när den är hemma igen.")
                                .font(.caption)
                                .foregroundStyle(Stil.väntar)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .kort(hörn: Stil.radhörn)
            } else {
                Text("Peka ut en mapp som ett Cowork-projekt läser, till exempel «00 Claude kontext» i kundens OneDrive. Kundkoll skriver dit det den vet om uppdraget och håller det uppdaterat. Inget råmaterial följer med.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let besked {
                Text(besked).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { mapp = Spegel.mapp(för: projekt) }
    }

    private func välj() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Välj mappen Cowork läser för \(projekt.namn). Kundkoll skriver en undermapp där."
        panel.prompt = "Använd"
        guard panel.runModal() == .OK, let vald = panel.url else { return }
        // En egen undermapp, så att spegeln aldrig blandas med det som redan ligger där.
        let mål = vald.lastPathComponent == "Kundkoll" ? vald : vald.appending(path: "Kundkoll")
        do {
            try Spegel.sätt(mål, för: projekt)
            mapp = mål
            skriv()
        } catch {
            besked = error.localizedDescription
        }
    }

    private func kopplaBort() {
        try? Spegel.sätt(nil, för: projekt)
        mapp = nil
        besked = "Spegeln är bortkopplad. Filerna ligger kvar i mappen."
    }

    private func skriv() {
        do {
            if let u = try Spegel.skriv(kund: kund, projekt: projekt, arkiv: arkiv) {
                besked = "Skrivet \(DateFormatter.klocka.string(from: Date())): \(u.rad)."
            } else {
                besked = "Mappen nås inte just nu."
            }
        } catch {
            besked = error.localizedDescription
        }
    }

    private func förkorta(_ väg: String) -> String {
        let hem = FileManager.default.homeDirectoryForCurrentUser.path
        var ut = väg
        if ut.hasPrefix(hem + "/Library/CloudStorage/") {
            ut = String(ut.dropFirst((hem + "/Library/CloudStorage/").count))
        } else if ut.hasPrefix(hem) {
            ut = "~" + ut.dropFirst(hem.count)
        }
        return ut
    }
}
