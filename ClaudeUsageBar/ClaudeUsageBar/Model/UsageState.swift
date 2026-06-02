import Foundation

struct UsageState: Equatable {
    var plan: String?
    var sessionPercent: Int?
    var sessionResetsIn: String?
    var weeklyPercent: Int?
    var weeklyResetsAt: String?
    var designPercent: Int?
    var scrapedAt: Date?
    var signedOut: Bool = false

    var isEmpty: Bool { sessionPercent == nil && weeklyPercent == nil }

    static let signedOut: UsageState = UsageState(signedOut: true)
}
