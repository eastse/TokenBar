import Foundation
import Observation
import TokenBarCore

/// Process-wide OAuth quota cache. All UI surfaces consume this single store
/// so opening the popover/settings window cannot fan out duplicate provider
/// requests.
@MainActor @Observable final class AgentUsageStore {
    static let shared = AgentUsageStore()
    static let didUpdateNotification = Notification.Name("TokenBarAgentUsageStoreDidUpdate")

    private(set) var payload: AgentUsagePayload?
    private var inFlight: Task<AgentUsagePayload?, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastRequestAt: Date?
    private var lastUsageSignature: Int64?

    private init() {}

    func startPolling(every seconds: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refreshIfStale(maxAge: seconds)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Refresh when the last actual network request is older than `maxAge`.
    /// Before hitting OAuth quota endpoints, compare the local total-token
    /// signature; if usage has not moved, keep the last quota payload.
    func refreshIfStale(maxAge: TimeInterval) async {
        if let inFlight {
            _ = await inFlight.value
            return
        }
        if let lastRequestAt, Date().timeIntervalSince(lastRequestAt) < maxAge {
            return
        }
        await refresh()
    }

    func refresh() async {
        if let inFlight {
            _ = await inFlight.value
            return
        }

        let usageSignature = await Self.currentUsageSignature()
        if payload != nil,
           let usageSignature,
           usageSignature == lastUsageSignature
        {
            return
        }

        let task = Task.detached(priority: .utility) {
            try? TBCore.agentUsage()
        }
        inFlight = task
        lastRequestAt = Date()
        let next = await task.value
        inFlight = nil

        if let usageSignature {
            lastUsageSignature = usageSignature
        }
        if let next {
            payload = next
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
        }
    }

    private static func currentUsageSignature() async -> Int64? {
        await Task.detached(priority: .utility) {
            try? TBCore.graph().summary.totalTokens
        }.value
    }
}
