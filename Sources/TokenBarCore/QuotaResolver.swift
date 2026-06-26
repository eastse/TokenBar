import Foundation

/// Picks which quota window the menu bar displays. Selection strings:
/// - `"auto"` — tightest window (lowest remaining %) across every agent.
/// - `"last_used"` — follow the agent the live trace shows as currently
///   active; falls back to `auto` when nothing is running.
/// - `"<clientId>|<windowLabel>"` — explicit pick.
public enum QuotaResolver {
    public static let auto = "auto"
    public static let lastUsed = "last_used"

    public static func selection(clientId: String, label: String) -> String {
        "\(clientId)|\(label)"
    }

    public static func resolve(
        payload: AgentUsagePayload?, trace: [TraceBucket] = [], selection: String
    ) -> (clientId: String, window: UsageWindow)? {
        guard let payload else { return nil }
        if selection.isEmpty || selection == Self.auto {
            return tightest(payload: payload)
        }
        if selection == Self.lastUsed {
            return followLastUsed(payload: payload, trace: trace)
                ?? tightest(payload: payload)
        }
        let parts = selection.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let agent = payload.agents.first(where: { $0.clientId == parts[0] }),
              let window = agent.windows.first(where: { $0.label == parts[1] })
        else { return nil }
        return (agent.clientId, window)
    }

    private static func tightest(
        payload: AgentUsagePayload
    ) -> (clientId: String, window: UsageWindow)? {
        var best: (clientId: String, window: UsageWindow)?
        for agent in payload.agents where agent.error == nil {
            for window in agent.windows where window.remainingPercent.isFinite {
                if best == nil || window.remainingPercent < best!.window.remainingPercent {
                    best = (agent.clientId, window)
                }
            }
        }
        return best
    }

    /// Tightest window inside the agent the trace marks as currently active
    /// (highest token bucket with a live rate). The trace's raw client ids
    /// (`claude-code`, `codex-cli`, …) map back to the short ids the quota
    /// snapshots use. Returns nil when nothing is live so the caller can fall
    /// back to global tightest.
    private static func followLastUsed(
        payload: AgentUsagePayload, trace: [TraceBucket]
    ) -> (clientId: String, window: UsageWindow)? {
        let active = trace.filter { $0.tokensPerMin > 0 }
            .max(by: { $0.tokens < $1.tokens })
        guard let active else { return nil }
        let id = normalizeTraceClient(active.client)
        guard let agent = payload.agents.first(where: { $0.clientId == id && $0.error == nil })
        else { return nil }
        var best: UsageWindow?
        for window in agent.windows where window.remainingPercent.isFinite {
            if best == nil || window.remainingPercent < best!.remainingPercent {
                best = window
            }
        }
        return best.map { (agent.clientId, $0) }
    }

    private static func normalizeTraceClient(_ id: String) -> String {
        switch id {
        case "claude-code": return "claude"
        case "codex-cli": return "codex"
        case "gemini-cli": return "gemini"
        default: return id.hasSuffix("-cli") ? String(id.dropLast(4)) : id
        }
    }
}
