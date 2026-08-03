import Foundation
import AppKit

/// Background-queue watchdog that force-relaunches Signoff if the main thread
/// stops responding for a sustained period.
///
/// The problem this solves: a SwiftUI render loop or re-entrant AppKit deadlock
/// pins the main thread without crashing the process. The app never exits, so the
/// OS never relaunches it, and the user is stuck on a frozen beach-balled menu
/// bar with no recovery. A self-rescue running ON the main thread is impossible
/// — it's the thread that's hung — so the watchdog runs on a background queue
/// and pings the main actor.
///
/// Mechanism: every `interval` seconds, schedule a `checkin` on the main thread
/// and a `tick` on the background queue. The next cycle, if the previous
/// `checkin` has not cleared, the main thread never ran it — it's hung. After
/// `maxMisses` consecutive misses (sustained hang, not a transient blip under a
/// heavy gen), the watchdog force-relaunches: terminate, then `open` the app
/// bundle so the user gets a fresh, responsive instance without a manual
/// Force Quit.
///
/// Disabled when `SIGNOFF_DISABLE_WATCHDOG` is set (dev: lets you pause in the
/// debugger on a deliberate main-thread stall without the watchdog fighting you)
/// and under a debugger attachment (detected via `getppid()!=1`, the cheap
/// Apple-platform proxy for a launched-by-debugger process).
///
/// NOTE on actor isolation: this class is intentionally NOT `@MainActor`. The
/// whole point is that it runs and can ACT when the main thread is hung. If it
/// were isolated to the main actor, a main-thread hang would deadlock the
/// watchdog too. The mutable `checkinPending`/`consecutiveMisses` fields are
/// touched only from the watchdog's own serial queue and the single
/// `DispatchQueue.main.async { checkinPending = false }` checkin — a benign,
/// single-writer/flag race that is correct for this threshold check.
/// `@unchecked Sendable`: the mutable fields (`didStart`, `checkinPending`,
/// `consecutiveMisses`) are confined to the watchdog's private serial queue
/// for all reads/writes — EXCEPT the single `DispatchQueue.main.async {
/// checkinPending = false }` checkin, a one-way flag flip that is benign under
/// the threshold read. `PersistenceController` in SignoffCore uses the same
/// pattern for its single-queue-confined mutable state. Swift 6 flags a plain
/// class singleton in `@Sendable` closures; the unchecked marker encodes the
/// by-design confinement that the compiler can't see.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "com.signoff.mainthread-watchdog", qos: .utility)
    private let interval: TimeInterval = 2.0
    private let maxMisses = 4   // ~8s of an unresponsive main thread before action

    private var didStart = false
    private var checkinPending = false
    private var consecutiveMisses = 0

    /// Arm the watchdog. Safe to call only once (idempotent). Called from the
    /// app delegate's `applicationDidFinishLaunching` — main actor at that
    /// point, but this method itself doesn't touch main-actor state.
    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startOnWatchdogQueue()
        }
    }

    // MARK: - Cycle (runs entirely on the watchdog queue — never the main actor)

    private func startOnWatchdogQueue() {
        guard !didStart else { return }
        didStart = true

        // Dev opt-out: never interfere while a developer is deliberately poking
        // the main thread under a debugger / environment flag.
        if ProcessInfo.processInfo.environment["SIGNOFF_DISABLE_WATCHDOG"] != nil { return }
        if isDebuggerLikelyAttached() {
            return
        }

        scheduleNext()
    }

    private func scheduleNext() {
        // Arm a checkin the main thread MUST clear; if it's still pending on
        // the next tick, it never ran the main actor — main thread is hung.
        checkinPending = true
        DispatchQueue.main.async { [weak self] in
            self?.checkinPending = false
        }

        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        // `checkinPending` is flipped to false ONLY on the main thread and
        // read here. Worst case is a one-cycle race; the threshold is a
        // sustained multi-second hang, not a single dropped ping.
        let missed = checkinPending

        if missed {
            consecutiveMisses += 1
        } else {
            consecutiveMisses = 0
        }

        if consecutiveMisses >= maxMisses {
            // Sustained hang confirmed. Relaunch off the main thread (it's
            // hung anyway); the relaunch itself doesn't need the main thread.
            relaunch()
            return
        }

        scheduleNext()
    }

    // MARK: - Relaunch (runs off the main thread by design)

    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let appPath = bundleURL.path

        // Launch the new instance FIRST so the relaunch survives our imminent
        // terminate. `open -n` forces a fresh launch even while the old PID
        // is technically still alive (about to be killed). This is a raw
        // fork+exec of `/usr/bin/open` — no AppKit, no main actor, works when
        // the main thread is wedged.
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", "-a", appPath]
        try? task.run()

        // Then force-exit this hung instance. `exit(0)` is the one thing that
        // reliably kills a process whose main thread is dead — NSApp.terminate
        // is main-actor-isolated and would itself stall. The fresh instance
        // is already launching, so a hard exit here loses nothing.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            exit(0)
        }
    }

    // MARK: - Debugger detection

    /// True when a process is likely launched under a debugger. A process
    /// launched normally (Finder, `open`, login item, relaunch via launchd)
    /// has a parent PID of 1. A process launched under lldb/Xcode has a parent
    /// PID that is the debugger's. Deliberately permissive — if a normal
    /// launch path ever looks like a debugger under here, the dev can set
    /// `SIGNOFF_DISABLE_WATCHDOG` to keep the watchdog out of the way.
    private func isDebuggerLikelyAttached() -> Bool {
        return getppid() != 1
    }
}

