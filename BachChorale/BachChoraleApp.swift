import SwiftUI
import CoreText

@main
struct BachChoraleApp: App {
    init() { registerFonts() }

    var body: some Scene {
        WindowGroup { ContentView() }
    }

    private func registerFonts() {
        for name in ["Bravura", "The Book"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
