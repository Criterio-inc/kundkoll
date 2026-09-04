import Foundation

extension Tester {
    static func ström() {
        Prov.svit("Strömmande svar")

        let öppen = #"{"choices":[{"delta":{"content":"Hej "}}]}"#
        Prov.lika(Chatt.deltaOpenAI(Data(öppen.utf8)), "Hej ",
                  "OpenAI-dialektens textbit plockas ur delta")
        let roll = #"{"choices":[{"delta":{"role":"assistant"}}]}"#
        Prov.lika(Chatt.deltaOpenAI(Data(roll.utf8)), nil,
                  "rader utan text ger ingenting")
        let slut = #"{"choices":[]}"#
        Prov.lika(Chatt.deltaOpenAI(Data(slut.utf8)), nil, "tomma val ger ingenting")

        let antro = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hej"}}"#
        Prov.lika(Chatt.deltaAnthropic(Data(antro.utf8)), "Hej",
                  "Anthropics text_delta plockas ur content_block_delta")
        let start = #"{"type":"message_start","message":{}}"#
        Prov.lika(Chatt.deltaAnthropic(Data(start.utf8)), nil,
                  "andra händelser ger ingenting")
        let tank = #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}"#
        Prov.lika(Chatt.deltaAnthropic(Data(tank.utf8)), nil,
                  "tänkande läcker inte in i svaret")
    }
}
