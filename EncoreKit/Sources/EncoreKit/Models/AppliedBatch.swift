import Foundation
import SwiftData

/// Records an imported batch ID to track sync and state export.
@Model
public final class AppliedBatch {
    #Index<AppliedBatch>([\.batchID])

    public var batchID: String = ""
    public var appliedAt: Date = Date.now

    public init(batchID: String = "", appliedAt: Date = Date.now) {
        self.batchID = batchID
        self.appliedAt = appliedAt
    }
}
