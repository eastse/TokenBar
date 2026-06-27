import Foundation

/// Picks which quota window the menu bar displays. Selection strings:
/// - `"lowest"` — tightest window (lowest remaining %) across every agent.
/// - `"last_used"` — follow the agent the live trace shows as currently
///   active; falls back to `lowest` when nothing is running.
/// - `"<clientId>|<windowLabel>"` — explicit pick.
/// - `"<clientId>|*"` — follow the tightest window within one agent.
public enum QuotaResolver {
    public static let lowest = "lowest"
    public static let lastUsed = "last_used"
    private static let legacyAuto = "auto"

    public static func normalizeSelection(_ selection: String?) -> String {
        guard let selection, !selection.isEmpty else { return lowest }
        return selection == legacyAuto ? lowest : selection
    }

    public static func selection(clientId: String, label: String) -> String {
        "\(clientId)|\(label)"
    }

    public static func agentSelection(clientId: String) -> String {
        "\(clientId)|*"
    }

    public static func resolve(
        payload: AgentUsagePayload?, trace: [TraceBucket] = [], selection: String
    ) -> (clientId: String, window: UsageWindow)? {
        guard let payload else { return nil }
        let selection = normalizeSelection(selection)
        if selection == Self.lowest {
            return tightest(payload: payload)
        }
        if selection == Self.lastUsed {
            return followLastUsed(payload: payload, trace: trace)
                ?? tightest(payload: payload)
        }
        let parts = selection.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let agent = payload.agents.first(where: { $0.clientId == parts[0] && $0.error == nil })
        else { return nil }
        if parts[1] == "*" {
            return tightest(agent: agent).map { (agent.clientId, $0) }
        }
        guard let window = agent.windows.first(where: { $0.label == parts[1] })
        else { return nil }
        return (agent.clientId, window)
    }

    public static func resolveAgent(
        payload: AgentUsagePayload?, trace: [TraceBucket] = [], selection: String
    ) -> AgentUsageSnapshot? {
        guard let payload,
              let pick = resolve(payload: payload, trace: trace, selection: selection)
        else { return nil }
        return payload.agents.first(where: { $0.clientId == pick.clientId && $0.error == nil })
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

    private static func tightest(agent: AgentUsageSnapshot) -> UsageWindow? {
        var best: UsageWindow?
        for window in agent.windows where window.remainingPercent.isFinite {
            if best == nil || window.remainingPercent < best!.remainingPercent {
                best = window
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
        return tightest(agent: agent).map { (agent.clientId, $0) }
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
