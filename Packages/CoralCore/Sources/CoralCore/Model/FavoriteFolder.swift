import Foundation

/// A bookmarked favorite folder for quick access in the sidebar.
public struct FavoriteFolder: Codable, Identifiable, Sendable, Hashable {
    public let id: String           // matches the SourceContainer.id
    public let name: String         // display name
    public let sourceType: String   // "filesystem", "smb", "photokit"

    public init(id: String, name: String, sourceType: String) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
    }
}

public enum FavoriteFolderStore {
    private static let key = "com.justmaple.coral-maple.favorites"

    public static func loadAll() -> [FavoriteFolder] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let favs = try? JSONDecoder().decode([FavoriteFolder].self, from: data) else {
            return []
        }
        return favs
    }

    public static func save(_ favs: [FavoriteFolder]) {
        if let data = try? JSONEncoder().encode(favs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func add(_ fav: FavoriteFolder) {
        var all = loadAll()
        if !all.contains(where: { $0.id == fav.id }) {
            all.append(fav)
            save(all)
        }
    }

    public static func remove(id: String) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        save(all)
    }

    public static func isFavorite(id: String) -> Bool {
        loadAll().contains { $0.id == id }
    }
}
