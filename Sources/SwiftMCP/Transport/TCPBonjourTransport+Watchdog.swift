#if Server
import Foundation

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Descriptor Watchdog

    /// How often the descriptor watchdog samples the process fd table, in seconds.
    internal static let watchdogInterval: UInt64 = 30

    /// The fraction of the descriptor limit past which the transport fails.
    internal static let watchdogThreshold = 0.8

    /// Watches the process descriptor table and fails the transport terminally
    /// when it approaches exhaustion.
    ///
    /// This has to be proactive sampling: under `EMFILE` an `NWListener` stays
    /// `.ready`, emits no state transition, and simply never accepts again — the
    /// server looks healthy from the outside while serving nothing, and a
    /// supervised daemon that never exits is never restarted. Failing while a
    /// few descriptors remain also leaves enough headroom to shut down cleanly.
    internal func startDescriptorWatchdog() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: TCPBonjourTransport.watchdogInterval * 1_000_000_000)
                } catch {
                    return  // cancelled
                }

                guard let self, await self.state.running() else { return }
                guard let usage = TCPBonjourTransport.descriptorUsage() else { continue }

                if Double(usage.used) >= TCPBonjourTransport.watchdogThreshold * Double(usage.limit) {
                    self.logger.critical("""
                        Process is running out of file descriptors \
                        (\(usage.used) of \(usage.limit) in use); \
                        failing the TCP+Bonjour transport terminally.
                        """)
                    await self.state.failTerminally(TransportError.resourceExhausted(
                        "File descriptors nearly exhausted (\(usage.used) of \(usage.limit) in use)."
                    ))
                    return
                }
            }
        }

        Task {
            await state.setWatchdogTask(task)
        }
    }

    /// How many descriptor-table slots one sample scans at most.
    internal static let watchdogScanCeiling = 65536

    /// Counts live descriptors against the process limit.
    ///
    /// Counting is `fcntl(fd, F_GETFD)` over the table — deliberately not
    /// `F_GETPATH` (returns `EBADF` for sockets, i.e. blind to exactly the leak
    /// this guards against) and not `proc_pidinfo` (reports table capacity, not
    /// usage). The *scan* is clamped (scanning billions of slots every sample
    /// is not an option), but `limit` is the real `rlim_cur`: comparing the
    /// threshold against the clamp would terminally fail a healthy deployment
    /// that raised `RLIMIT_NOFILE` and legitimately holds many descriptors.
    /// When the limit exceeds the scan window the watchdog is naturally inert —
    /// a clamped scan cannot prove proximity to a limit it cannot see, and an
    /// effectively unlimited `rlim_cur` cannot be exhausted by sockets anyway.
    internal static func descriptorUsage() -> (used: Int, limit: Int)? {
        var limits = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limits) == 0 else { return nil }

        let limit = Int(clamping: limits.rlim_cur)
        let scanCeiling = min(limit, watchdogScanCeiling)
        guard scanCeiling > 0 else { return nil }

        var used = 0
        for descriptor in 0..<Int32(scanCeiling) where fcntl(descriptor, F_GETFD) != -1 {
            used += 1
        }
        return (used, limit)
    }
}
#endif
#endif
