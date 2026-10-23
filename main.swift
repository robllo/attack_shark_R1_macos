// r1 command-line tool. Build with ./build.sh
import Foundation
import IOKit.hid

var reportTimes: [Double] = []

// Counts pointer reports straight from USB; browsers cap at the display refresh rate, so they can't measure this.
func measureRate(_ device: IOHIDDevice) {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { _, _, _, _, _, _, _ in
        reportTimes.append(CFAbsoluteTimeGetCurrent())
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    print("move the mouse in fast circles...")
    let start = Date()
    while reportTimes.isEmpty && Date().timeIntervalSince(start) < 60 { CFRunLoopRunInMode(.defaultMode, 0.1, true) }
    guard let first = reportTimes.first else { fail("no movement seen within 60 s") }
    while CFAbsoluteTimeGetCurrent() - first < 3 { CFRunLoopRunInMode(.defaultMode, 0.1, true) }
    // Peak over 100 ms windows: pauses in movement send nothing and would drag an average down.
    var peak = 0
    for t in reportTimes { peak = max(peak, reportTimes.filter { $0 >= t && $0 < t + 0.1 }.count) }
    print("peak report rate: ~\(peak * 10) Hz (\(reportTimes.count) reports in 3 s)")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func run<T>(_ body: () throws -> T) -> T {
    do { return try body() } catch { fail(error.localizedDescription) }
}

let usage = """
usage:
  r1 battery
  r1 dpi <d1> <d2> <d3> <d4> <d5> <d6> [--active N] [--angle-snap] [--ripple]
        six stages, 100-18000 in steps of 100; active stage 1-6 (default 1)
  r1 polling <125|250|500|1000>
  r1 sleep <seconds 0.5-30> <deep-sleep minutes 1-60> <debounce ms 4-50, even>
  r1 buttons <button>=<action> ...
        buttons: left right middle back forward dpi scroll-up scroll-down
        actions: left-click right-click middle-click back forward double-click disable
                 dpi-cycle dpi+ dpi- scroll-up scroll-down play-pause next-track prev-track
                 mute vol+ vol-, or a key combo like cmd+c, ctrl+up, cmd+shift+4, f13
        the dpi button only accepts dpi-cycle, dpi+ or dpi-; buttons left out go back to their factory action
  r1 rate        measure the real polling rate (move the mouse while it runs)
  r1 selftest
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }
args.removeFirst()

switch command {
case "selftest":
    selfTest()
case "battery":
    let (device, wired) = run { try openMouse() }
    if let b = run({ try readBattery(device, wired: wired) }) {
        print("battery: \(b.percent)%\(b.charging ? " (charging)" : "")")
    } else {
        print("wired: charging (the cable connection does not report a percentage)")
    }
case "buttons":
    var assignments: [String: (UInt8, UInt8, UInt8)] = [:]
    for arg in args {
        let kv = arg.lowercased().split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2, buttonOffsets[kv[0]] != nil else { fail("unknown button in '\(arg)'\n\n" + usage) }
        guard let action = parseAction(kv[1]) else { fail("unknown action in '\(arg)'\n\n" + usage) }
        guard kv[0] != "dpi" || dpiButtonActions.contains(kv[1]) else { fail("the R1 DPI button only accepts dpi-cycle, dpi+ or dpi-") }
        assignments[kv[0]] = action
    }
    run { try send(openMouse().0, buttonReport(assignments)) }
    print("buttons set: " + (assignments.isEmpty ? "factory defaults" : args.joined(separator: " ")))
case "rate":
    measureRate(run { try openMouse(usage: 0x02) }.0)
case "dpi":
    let angleSnap = args.contains("--angle-snap"), ripple = args.contains("--ripple")
    var active = 1
    if let i = args.firstIndex(of: "--active"), i + 1 < args.count, let n = Int(args[i + 1]) {
        active = n
        args.removeSubrange(i...i + 1)
    }
    let dpis = args.filter { !$0.hasPrefix("--") }.compactMap(Int.init)
    guard let report = dpiReport(dpis, active: active, angleSnap: angleSnap, ripple: ripple) else { fail(usage) }
    run { try send(openMouse().0, report) }
    print("dpi set: \(dpis.map(String.init).joined(separator: " ")), active stage \(active)")
case "polling":
    guard let hz = args.first.flatMap(Int.init), let report = pollingReport(hz) else { fail(usage) }
    run { try send(openMouse().0, report) }
    print("polling rate set: \(hz) Hz")
case "sleep":
    guard args.count == 3, let s = Double(args[0]), let d = Int(args[1]), let k = Int(args[2]),
          let report = sleepReport(seconds: s, deepMinutes: d, debounceMs: k) else { fail(usage) }
    run { try send(openMouse().0, report) }
    print("sleep set: \(s) s, deep sleep \(d) min, debounce \(k) ms")
default:
    fail(usage)
}
