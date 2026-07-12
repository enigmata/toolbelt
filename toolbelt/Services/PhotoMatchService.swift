import Foundation
import SwiftData
import Vision

/// On-device identify-by-photo: Vision feature prints of the query image are
/// compared against every stored tool photo; tools rank by their closest
/// photo. No network, no training. Prints are cached in memory per photo —
/// cheap to recompute and avoids persisting Vision's observation format.
@MainActor
final class PhotoMatchService {
    static let shared = PhotoMatchService()

    struct Match: Identifiable {
        let tool: Tool
        let distance: Double
        var id: PersistentIdentifier { tool.persistentModelID }

        /// Rough confidence bucket for display.
        var confidence: String {
            switch distance {
            case ..<0.4: "Strong match"
            case ..<0.7: "Possible match"
            default: "Weak match"
            }
        }
    }

    private var printCache: [PersistentIdentifier: FeaturePrintObservation] = [:]

    /// Tools ranked by minimum feature-print distance across their photos.
    func rankTools(matching queryImage: Data, in tools: [Tool], maxResults: Int = 5) async throws -> [Match] {
        let queryPrint = try await Self.featurePrint(for: queryImage)

        var best: [(tool: Tool, distance: Double)] = []
        for tool in tools {
            var minDistance: Double?
            for photo in tool.photos ?? [] {
                guard let print = await cachedPrint(for: photo) else { continue }
                if let distance = try? queryPrint.distance(to: print) {
                    minDistance = min(minDistance ?? .greatestFiniteMagnitude, distance)
                }
            }
            if let minDistance {
                best.append((tool, minDistance))
            }
        }

        return best
            .sorted { $0.distance < $1.distance }
            .prefix(maxResults)
            .map { Match(tool: $0.tool, distance: $0.distance) }
    }

    private func cachedPrint(for photo: ToolPhoto) async -> FeaturePrintObservation? {
        let id = photo.persistentModelID
        if let cached = printCache[id] {
            return cached
        }
        guard let print = try? await Self.featurePrint(for: photo.data) else { return nil }
        printCache[id] = print
        return print
    }

    /// CPU-bound Vision work; the request runs off the calling actor.
    private static func featurePrint(for imageData: Data) async throws -> FeaturePrintObservation {
        let request = GenerateImageFeaturePrintRequest()
        return try await request.perform(on: imageData)
    }
}
