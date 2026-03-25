import Foundation
import EventKit
import CryptoKit

extension EKEvent {
    /// Generates a stable checksum of the event's content to detect changes.
    var syncChecksum: String {
        var components = [
            title ?? "",
            notes ?? "",
            location ?? "",
            startDate.description,
            endDate.description,
            String(isAllDay)
        ]
        
        // Add recurrence rules if any
        if let rules = recurrenceRules {
            for rule in rules {
                components.append(rule.description)
            }
        }
        
        let combined = components.joined(separator: "|")
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
