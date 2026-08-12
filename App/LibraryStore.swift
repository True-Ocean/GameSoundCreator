import AudioGenCore
import Foundation

struct LibraryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var savedAt: Date
    var intent: SoundIntent
    var exportFileName: String?

    init(intent: SoundIntent, exportFileName: String? = nil) {
        self.id = UUID()
        self.savedAt = Date()
        self.intent = intent
        self.exportFileName = exportFileName
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var entries: [LibraryEntry] = []
    @Published private(set) var loadError: String?
    private let fileName = "library.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([LibraryEntry].self, from: data)
            entries.sort { $0.savedAt > $1.savedAt }
            loadError = nil
        } catch {
            let backupURL = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("library-corrupt-\(UUID().uuidString).json")
            if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) != nil {
                loadError = "ライブラリを読み込めなかったため、破損したデータを \(backupURL.lastPathComponent) として退避しました。"
            } else {
                loadError = "ライブラリを読み込めませんでした。"
            }
            entries = []
        }
    }

    func save(_ intent: SoundIntent, exportFileName: String? = nil) throws {
        var next = intent
        if next.seed == nil {
            next.seed = UInt64.random(in: 1...999_999)
        }
        let previous = entries
        entries.insert(LibraryEntry(intent: next, exportFileName: exportFileName), at: 0)
        do {
            try persist()
        } catch {
            entries = previous
            throw error
        }
    }

    func remove(_ entry: LibraryEntry) throws {
        let previous = entries
        entries.removeAll { $0.id == entry.id }
        do {
            try persist()
        } catch {
            entries = previous
            throw error
        }
    }

    var recent: [LibraryEntry] {
        Array(entries.prefix(8))
    }

    /// Returns a recovery notice once so revisiting the library does not repeat it.
    func consumeLoadError() -> String? {
        defer { loadError = nil }
        return loadError
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
