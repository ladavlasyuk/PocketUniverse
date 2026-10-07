import UIKit

final class ProfileManager {
    static let shared = ProfileManager()

    private let nameKey = "player_display_name"
    private let photoFileName = "player_portrait.jpg"

    private var cachedPortrait: UIImage?

    private init() {}

    var displayName: String {
        get {
            let stored = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let stored, !stored.isEmpty else { return "Cosmic Explorer" }
            return stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: nameKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: nameKey)
            }
            NotificationCenter.default.post(name: .playerProfileDidChange, object: nil)
        }
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "CE" : letters.joined()
    }

    var hasPortrait: Bool {
        FileManager.default.fileExists(atPath: portraitAddress().path)
    }

    func portrait() -> UIImage? {
        if let cachedPortrait {
            return cachedPortrait
        }
        guard let data = try? Data(contentsOf: portraitAddress()),
              let image = UIImage(data: data) else {
            return nil
        }
        cachedPortrait = image
        return image
    }

    @discardableResult
    func savePortrait(_ image: UIImage) -> Bool {
        let normalized = squareThumbnail(from: image, side: 640)
        guard let data = normalized.jpegData(compressionQuality: 0.9) else { return false }

        do {
            try data.write(to: portraitAddress(), options: [.atomic])
            cachedPortrait = normalized
            NotificationCenter.default.post(name: .playerProfileDidChange, object: nil)
            return true
        } catch {
            print("[Profile] Failed to store portrait: \(error.localizedDescription)")
            return false
        }
    }

    func removePortrait() {
        cachedPortrait = nil
        try? FileManager.default.removeItem(at: portraitAddress())
        NotificationCenter.default.post(name: .playerProfileDidChange, object: nil)
    }

    private func portraitAddress() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(photoFileName)
    }

    private func squareThumbnail(from image: UIImage, side: CGFloat) -> UIImage {
        let minimumSide = min(image.size.width, image.size.height)
        guard minimumSide > 0 else { return image }

        let cropRect = CGRect(
            x: (image.size.width - minimumSide) / 2,
            y: (image.size.height - minimumSide) / 2,
            width: minimumSide,
            height: minimumSide
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)

        return renderer.image { _ in
            let target = CGRect(
                x: -cropRect.origin.x * side / minimumSide,
                y: -cropRect.origin.y * side / minimumSide,
                width: image.size.width * side / minimumSide,
                height: image.size.height * side / minimumSide
            )
            image.draw(in: target)
        }
    }
}

extension Notification.Name {
    static let playerProfileDidChange = Notification.Name("playerProfileDidChange")
    static let playerSettingsDidChange = Notification.Name("playerSettingsDidChange")
}
