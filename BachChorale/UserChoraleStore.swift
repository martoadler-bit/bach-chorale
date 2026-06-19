import Foundation
import Combine

struct UserChoraleEntry: Identifiable, Codable {
    let id: UUID
    var name: String
    var date: Date
    var chorale: ChoraleData
    var sopranoNotes: [MelodyNote]
}

class UserChoraleStore: ObservableObject {
    static let shared = UserChoraleStore()

    @Published var entries: [UserChoraleEntry] = []

    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_chorales.json")
    }

    private init() {
        load()
    }

    func save(_ entry: UserChoraleEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        persist()
    }

    func delete(_ entry: UserChoraleEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("UserChoraleStore persist error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            entries = try JSONDecoder().decode([UserChoraleEntry].self, from: data)
        } catch {
            print("UserChoraleStore load error: \(error)")
        }
    }
}
