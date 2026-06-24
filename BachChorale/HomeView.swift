import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.white.opacity(0.85))
                        Text("Choral Lab")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("Bach Chorale Harmonizer")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 44)

                    // Cards
                    VStack(spacing: 16) {
                        HomeCard(
                            icon: "books.vertical.fill",
                            color: Color(red: 0.30, green: 0.55, blue: 0.90),
                            title: "Library",
                            subtitle: "Browse 410 J.S. Bach chorales"
                        ) { selectedTab = 4 }

                        HomeCard(
                            icon: "pianokeys",
                            color: Color(red: 0.35, green: 0.72, blue: 0.45),
                            title: "Harmonize Melody",
                            subtitle: "Draw a soprano line and generate SATB voices"
                        ) { selectedTab = 1 }

                        HomeCard(
                            icon: "wand.and.stars",
                            color: Color(red: 0.75, green: 0.45, blue: 0.90),
                            title: "Generate Chorale",
                            subtitle: "Create a complete four-part chorale from scratch"
                        ) { selectedTab = 2 }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

private struct HomeCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(18)
            .background(Color.white.opacity(0.07))
            .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
}
