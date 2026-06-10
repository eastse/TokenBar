import AppKit
import TokenBarCore

/// App bootstrap: accessory activation policy (menu-bar only, no Dock icon),
/// the status-item controller, and the 60s tray-title refresh loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let titleRefreshSecs: UInt64 = 60

    private var statusController: StatusItemController?
    private var titleRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusItemController()
        statusController = controller
        startTitleRefresh()

        // Debug hook: `swift run TokenBar --open-popover` shows the popover
        // shortly after launch so it can be screenshotted without a click.
        if CommandLine.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                controller.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleRefreshTask?.cancel()
    }

    /// Refreshes the tray title with today's token total every 60s. Cheap:
    /// tb_graph serves a <=30s staticlib cache on top of tokscale's own cache.
    /// Placeholder for the full title-mode system in a later phase.
    private func startTitleRefresh() {
        titleRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let graph = try? await Task.detached(priority: .utility) {
                    try TBCore.graph()
                }.value
                guard !Task.isCancelled else { break }
                if let graph {
                    self?.statusController?.updateTitle(
                        Format.compactTokens(Format.todayTokens(in: graph)))
                }
                try? await Task.sleep(for: .seconds(Double(Self.titleRefreshSecs)))
            }
        }
    }
}
