import Foundation

public struct DatasetItem: Codable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
}

public final class DatasetProvider {
    public enum ProviderError: Error {
        case resourceMissing
        case decodeFailed
    }

    private let items: [DatasetItem]

    public convenience init() throws {
        try self.init(bundle: .module)
    }

    public init(items: [DatasetItem]) {
        self.items = items
    }

    public init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "ImageDataset", withExtension: "json") else {
            throw ProviderError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        guard let decoded = try? JSONDecoder().decode([DatasetItem].self, from: data) else {
            throw ProviderError.decodeFailed
        }
        self.items = decoded
    }

    public func totalCount() -> Int { items.count }

    public static func fallbackItems(count: Int = 240) -> [DatasetItem] {
        let n = max(0, count)
        return (0..<n).compactMap { idx in
            let id = String(idx + 1)
            guard let url = URL(string: "https://picsum.photos/id/\(idx + 10)/800/800") else { return nil }
            return DatasetItem(id: id, url: url, title: "Image \(idx + 1)")
        }
    }

    public func page(offset: Int, limit: Int) -> [DatasetItem] {
        guard offset < items.count else { return [] }
        let end = min(items.count, offset + max(0, limit))
        return Array(items[offset..<end])
    }
}
