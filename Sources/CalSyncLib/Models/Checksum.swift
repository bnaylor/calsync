import Foundation
import CryptoKit

public enum Checksum {
    nonisolated(unsafe) private static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func compute(
        title: String,
        description: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        status: String
    ) -> String {
        let components = [
            title,
            description ?? "\0nil",
            location ?? "\0nil",
            utcFormatter.string(from: startDate),
            utcFormatter.string(from: endDate),
            String(isAllDay),
            status
        ]
        let combined = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
