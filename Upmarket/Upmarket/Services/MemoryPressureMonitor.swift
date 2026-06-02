import Dispatch
import Foundation
import OSLog

@MainActor
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private var source: DispatchSourceMemoryPressure?

    private init() {}

    func start() {
        guard source == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue(label: "UpmarketMemoryPressure")
        )
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            Task { @MainActor in
                self?.handle(source.data)
            }
        }
        source.resume()
        self.source = source
    }

    private func handle(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            AppLog.diagnostics.error("Critical memory pressure signal received")
            ConversionQueue.shared.handleMemoryPressureCritical()
        } else if event.contains(.warning) {
            AppLog.diagnostics.warning("Memory pressure warning signal received")
        }
    }
}
