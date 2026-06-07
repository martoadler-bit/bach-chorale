import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioEngine()
    @State private var selectedChord: Chord? = nil
    @State private var navigateTo: Chord? = nil
    @State private var showSettings = false

    var body: some View {
        TabView {
            exploreTab
                .tabItem {
                    Label(LocalizedStringKey("tab.explore"), systemImage: "circle.hexagongrid.fill")
                }

            TheoryView()
                .tabItem {
                    Label(LocalizedStringKey("tab.theory"), systemImage: "text.book.closed.fill")
                }
        }
        .tint(.yellow)
        .background(Color.black)
        // Force dark/black appearance on tab bar
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(white: 0.07, alpha: 1)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .onChange(of: navigateTo) { chord in
            if let chord {
                selectedChord = chord
                navigateTo = nil
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(audio: audio)
        }
    }

    // MARK: - Explore Tab

    private var exploreTab: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("app.title"))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text(LocalizedStringKey("app.subtitle"))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    // Stop — always visible, dims when nothing is playing
                    Button {
                        audio.stopAll()
                        selectedChord = nil
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(audio.activePitchClasses.isEmpty
                                ? Color.white.opacity(0.08)
                                : Color.red.opacity(0.75))
                            .clipShape(Circle())
                    }
                    .animation(.easeInOut(duration: 0.2), value: audio.activePitchClasses.isEmpty)

                    // Settings
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 6)

                // Legend
                HStack(spacing: 14) {
                    LegendItem(shape: AnyShape(RoundedRectangle(cornerRadius: 3)), color: .blue, labelKey: "legend.major")
                    LegendItem(shape: AnyShape(Circle()), color: .teal, labelKey: "legend.minor")
                    LegendItem(shape: AnyShape(Diamond()), color: .purple, labelKey: "legend.aug")
                    Spacer()
                    Text(LocalizedStringKey(audio.currentPreset.localizedKey))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                // Cube Dance
                CubeDanceView(audio: audio, selectedChord: $selectedChord)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)

                // Operations panel
                OperationsPanel(selectedChord: selectedChord, audio: audio, navigateTo: $navigateTo)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Legend Item

struct LegendItem<S: Shape>: View {
    let shape: S
    let color: Color
    let labelKey: String

    init(shape: S, color: Color, labelKey: String) {
        self.shape = shape
        self.color = color
        self.labelKey = labelKey
    }

    var body: some View {
        HStack(spacing: 4) {
            shape
                .fill(color.opacity(0.8))
                .frame(width: 10, height: 10)
            Text(LocalizedStringKey(labelKey))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// AnyShape wrapper so LegendItem can accept different shape types
struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = { shape.path(in: $0) } }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @ObservedObject var audio: AudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(LocalizedStringKey("settings.sound"))) {
                    ForEach(SoundPreset.allCases) { preset in
                        Button {
                            audio.currentPreset = preset
                        } label: {
                            HStack {
                                Text(LocalizedStringKey(preset.localizedKey))
                                    .foregroundColor(.primary)
                                Spacer()
                                if audio.currentPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        showAbout = true
                    } label: {
                        HStack {
                            Text(LocalizedStringKey("about.title"))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey("settings.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("settings.done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}
