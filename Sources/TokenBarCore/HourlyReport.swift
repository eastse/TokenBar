import Foundation

// Per-hour report (`HourlyReport` in types.ts).

public struct HourlyClientEntry: Decodable, Sendable {
    public let client: String
    public let input: Int64
    public let output: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let reasoning: Int64
    public let total: Int64
    public let messageCount: Int
    public let turnCount: Int
    public let cost: Double
}

public struct HourlyReportEntry: Decodable, Sendable {
    /// "YYYY-MM-DD HH:00" local-time slot.
    public let hour: String
    public let clients: [String]
    public let models: [String]
    public let clientBreakdown: [HourlyClientEntry]
    public let input: Int64
    public let output: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let reasoning: Int64
    public let total: Int64
    public let messageCount: Int
    public let turnCount: Int
    public let cost: Double

    private enum CodingKeys: String, CodingKey {
        case hour
        case clients
        case models
        case clientBreakdown
        case input
        case output
        case cacheRead
        case cacheWrite
        case reasoning
        case total
        case messageCount
        case turnCount
        case cost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hour = try container.decode(String.self, forKey: .hour)
        clients = try container.decode([String].self, forKey: .clients)
        models = try container.decode([String].self, forKey: .models)
        clientBreakdown = try container.decodeIfPresent([HourlyClientEntry].self, forKey: .clientBreakdown) ?? []
        input = try container.decode(Int64.self, forKey: .input)
        output = try container.decode(Int64.self, forKey: .output)
        cacheRead = try container.decode(Int64.self, forKey: .cacheRead)
        cacheWrite = try container.decode(Int64.self, forKey: .cacheWrite)
        reasoning = try container.decode(Int64.self, forKey: .reasoning)
        total = try container.decode(Int64.self, forKey: .total)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        turnCount = try container.decode(Int.self, forKey: .turnCount)
        cost = try container.decode(Double.self, forKey: .cost)
    }
}

public struct HourlyReport: Decodable, Sendable {
    public let entries: [HourlyReportEntry]
    public let totalCost: Double
}
