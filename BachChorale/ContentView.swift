import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChoraleViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            SopranoInputView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Soprano", systemImage: "music.note") }
                .tag(1)

            GenerateView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Generate", systemImage: "wand.and.stars") }
                .tag(2)

            ChoraleResultView(vm: vm)
                .tabItem { Label("Chorale", systemImage: "music.quarternote.3") }
                .tag(3)

            LibraryView(vm: vm, selectedTab: $selectedTab)
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(4)

            TheoryView()
                .tabItem { Label("Theory", systemImage: "graduationcap") }
                .tag(5)
        }
        .preferredColorScheme(.dark)
    }
}
