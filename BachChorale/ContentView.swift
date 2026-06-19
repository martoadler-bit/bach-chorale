import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChoraleViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SopranoInputView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Soprano", systemImage: "music.note") }
                .tag(0)

            GenerateView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Generate", systemImage: "wand.and.stars") }
                .tag(1)

            ChoraleResultView(vm: vm)
                .tabItem { Label("Chorale", systemImage: "music.quarternote.3") }
                .tag(2)

            LibraryView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(3)

            TheoryView()
                .tabItem { Label("Theory", systemImage: "graduationcap") }
                .tag(4)
        }
        .preferredColorScheme(.dark)
    }
}
