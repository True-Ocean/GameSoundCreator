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
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var entries: [LibraryEntry] = []
    private let fileName = "library.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LibraryEntry].self, from: data)) ?? []
        entries.sort { $0.savedAt > $1.savedAt }
    }

    func save(_ intent: SoundIntent, exportFileName: String? = nil) throws {
        var next = intent
        if next.seed == nil {
            next.seed = UInt64.random(in: 1...999_999)
        }
        entries.insert(LibraryEntry(intent: next, exportFileName: exportFileName), at: 0)
        if entries.count > 50 {
            entries = Array(entries.prefix(50))
        }
        try persist()
    }

    func remove(_ entry: LibraryEntry) throws {
        entries.removeAll { $0.id == entry.id }
        try persist()
    }

    var recent: [LibraryEntry] {
        Array(entries.prefix(8))
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
