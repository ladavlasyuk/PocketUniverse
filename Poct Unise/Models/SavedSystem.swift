import Foundation

struct SavedSystem: Codable, Identifiable {
    var id: UUID
    var number: Int
    var starCount: Int
    var planetCount: Int
    var collisionCount: Int
    var lifetimeMinutes: Int
    var createdAt: Date
    var levelName: String

    init(number: Int, starCount: Int, planetCount: Int, collisionCount: Int, lifetimeMinutes: Int, levelName: String) {
        self.id = UUID()
        self.number = number
        self.starCount = starCount
        self.planetCount = planetCount
        self.collisionCount = collisionCount
        self.lifetimeMinutes = lifetimeMinutes
        self.createdAt = Date()
        self.levelName = levelName
    }

    var cardTitle: String {
        "System #\(number)"
    }

    var summaryLine: String {
        "⭐ \(starCount) stars, 🪐 \(planetCount) planets, ☄️ \(collisionCount) collisions, ⏱ \(lifetimeMinutes) min lifetime"
    }
}

final class SystemStore {
    static let shared = SystemStore()

    private let fileName = "saved_systems.json"

    private init() {}

    private var fileAddress: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }

    func fetchAll() -> [SavedSystem] {
        guard let data = try? Data(contentsOf: fileAddress),
              let systems = try? JSONDecoder().decode([SavedSystem].self, from: data) else {
            return []
        }
        return systems.sorted { $0.number > $1.number }
    }

    func save(_ snapshot: SessionSnapshot) {
        var systems = fetchAll()
        let number = (systems.map(\.number).max() ?? 0) + 1
        let record = SavedSystem(
            number: number,
            starCount: snapshot.stars,
            planetCount: snapshot.planets,
            collisionCount: snapshot.collisions,
            lifetimeMinutes: snapshot.lifetimeMinutes,
            levelName: snapshot.levelName
        )
        systems.append(record)
        persist(systems)
    }

    private func persist(_ systems: [SavedSystem]) {
        guard let data = try? JSONEncoder().encode(systems) else { return }
        try? data.write(to: fileAddress, options: [.atomic])
    }
}
