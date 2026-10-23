// Attack Shark R1 protocol and HID transport for macOS (IOKit, no dependencies). Shared by the CLI and the app.
// Protocol ported from jlucaso1/attack-shark-r1 (Rust), ThachRC/Attack-Shark-R1-Linux (Qt)
// and akawazak/attack-shark-x11-community-driver (button map).
import Foundation
import IOKit.hid

let vendorID = 0x1d57
let productIDs = [0xfa60 /* 2.4G dongle */, 0xfa61 /* USB-C cable */]

// Hardware DPI codes for 100...18000 in steps of 100; index = dpi / 100 - 1.
let dpiTable: [UInt8] = [
    0x02, 0x04, 0x06, 0x09, 0x0b, 0x0e, 0x10, 0x12, 0x15, 0x17,
    0x19, 0x1c, 0x1e, 0x20, 0x23, 0x25, 0x27, 0x2a, 0x2c, 0x2f,
    0x31, 0x33, 0x36, 0x38, 0x3a, 0x3d, 0x3f, 0x41, 0x44, 0x46,
    0x48, 0x4b, 0x4d, 0x4f, 0x52, 0x54, 0x57, 0x59, 0x5b, 0x5e,
    0x60, 0x62, 0x65, 0x67, 0x69, 0x6c, 0x6e, 0x70, 0x73, 0x75,
    0x77, 0x7a, 0x7c, 0x7f, 0x81, 0x83, 0x86, 0x88, 0x8a, 0x8d,
    0x8f, 0x91, 0x94, 0x96, 0x98, 0x9b, 0x9d, 0x9f, 0xa2, 0xa4,
    0xa7, 0xa9, 0xab, 0xae, 0xb0, 0xb2, 0xb5, 0xb7, 0xb9, 0xbc,
    0xbe, 0xc0, 0xc3, 0xc5, 0xc7, 0xca, 0xcc, 0xcf, 0xd1, 0xd3,
    0xd6, 0xd8, 0xda, 0xdd, 0xdf, 0xe1, 0xe4, 0xe6, 0xe8, 0xeb,
    0x76, 0x77, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7f, 0x80, 0x81,
    0x82, 0x83, 0x84, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8d,
    0x8e, 0x8f, 0x90, 0x91, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
    0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa1, 0xa2, 0xa3, 0xa4,
    0xa5, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xae, 0xaf, 0xb0,
    0xb1, 0xb2, 0xb3, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xbb, 0xbc,
    0xbd, 0xbe, 0xbf, 0xc0, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7,
    0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3,
]

func dpiCode(_ dpi: Int) -> UInt8? {
    guard (100...18000).contains(dpi), dpi % 100 == 0 else { return nil }
    return dpiTable[dpi / 100 - 1]
}

// Feature report 0x04: six DPI stages, active stage, angle snap, ripple control.
func dpiReport(_ dpis: [Int], active: Int, angleSnap: Bool, ripple: Bool) -> [UInt8]? {
    guard dpis.count == 6, (1...6).contains(active) else { return nil }
    var p = [UInt8](repeating: 0, count: 56)
    p[0] = 0x04; p[1] = 0x38; p[2] = 0x01
    p[3] = angleSnap ? 1 : 0
    p[4] = ripple ? 1 : 0
    p[5] = 0x3f
    for (i, dpi) in dpis.enumerated() {
        guard let code = dpiCode(dpi) else { return nil }
        p[8 + i] = code
        p[16 + i] = (10100...12000).contains(dpi) ? 1 : 0
        if dpi > 12000 { p[6] |= 1 << i }
    }
    p[7] = p[6]
    p[24] = UInt8(active)
    p.replaceSubrange(25..<50, with: [0xff, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0xff, 0xff,
                                      0xff, 0x00, 0x00, 0xff, 0xff, 0xff, 0x00, 0xff, 0xff, 0x40,
                                      0x00, 0xff, 0xff, 0xff, 0x02])
    let sum = p[3..<50].reduce(0) { $0 + Int($1) }
    p[50] = UInt8((sum >> 8) & 0xff)
    p[51] = UInt8(sum & 0xff)
    return p
}

// Feature report 0x06: polling rate.
func pollingReport(_ hz: Int) -> [UInt8]? {
    let codes: [Int: (UInt8, UInt8)] = [125: (0x08, 0xf7), 250: (0x04, 0xfb), 500: (0x02, 0xfd), 1000: (0x01, 0xfe)]
    guard let (lo, hi) = codes[hz] else { return nil }
    return [0x06, 0x09, 0x01, lo, hi, 0, 0, 0, 0]
}

// Feature report 0x05: sleep delay (0.5-30 s), deep sleep (1-60 min), debounce (4-50 ms, even).
// shortcut: only the Rust driver documents this layout for the R1, verify on hardware before trusting edge values.
func sleepReport(seconds: Double, deepMinutes: Int, debounceMs: Int) -> [UInt8]? {
    guard (0.5...30).contains(seconds), (1...60).contains(deepMinutes),
          (4...50).contains(debounceMs), debounceMs % 2 == 0 else { return nil }
    let ds = UInt8(deepMinutes)
    var p: [UInt8] = [0x05, 0x0f, 0x01, 0x00, 0x03, 0x18, 0x00, 0x00, 0xff, 0x04, 0x02, 0x01, 0x20, 0x00, 0x00]
    p[4] = 0x03 | (ds & 0xf0)
    p[5] = 0x08 | ((ds & 0x0f) << 4)
    p[9] = UInt8(seconds * 2)
    p[10] = UInt8(debounceMs / 2)
    p[12] = ((((ds & 0x0f) &+ (ds >> 4)) & 0x0f) << 4) &+ 0x0a &+ p[9] &+ p[10]
    return p
}

// Feature report 0x08: the whole button map, 3 bytes per button (action, modifiers, key).
// Ported from akawazak/attack-shark-x11-community-driver (MacrosBuilder), which drives the R1 dongle the same way,
// except the DPI button: on the R1 it sits at offset 12 (18 on the X11), found by probing a real mouse.
let buttonOffsets = ["left": 3, "right": 6, "middle": 9, "dpi": 12, "forward": 21, "back": 24, "scroll-up": 51, "scroll-down": 54]
let namedActions: [String: UInt8] = [
    "disable": 0x01, "left-click": 0x02, "right-click": 0x03, "middle-click": 0x04, "back": 0x05, "forward": 0x06,
    "double-click": 0x07, "scroll-up": 0x09, "scroll-down": 0x0a, "dpi-cycle": 0x0d, "dpi+": 0x0e, "dpi-": 0x0f,
    "prev-track": 0x16, "next-track": 0x17, "play-pause": 0x18, "mute": 0x1a, "vol+": 0x1b, "vol-": 0x1c,
]
// The R1's DPI slot ignores keys; only DPI functions were seen to work there.
let dpiButtonActions = ["dpi-cycle", "dpi+", "dpi-"]
let modifierBits: [String: UInt8] = ["ctrl": 0x01, "shift": 0x02, "alt": 0x04, "opt": 0x04, "cmd": 0x08, "win": 0x08]
let keyCodes: [String: UInt8] = {
    var k: [String: UInt8] = ["enter": 0x28, "esc": 0x29, "delete": 0x2a, "tab": 0x2b, "space": 0x2c,
                              "-": 0x2d, "=": 0x2e, "[": 0x2f, "]": 0x30, "\\": 0x31, ";": 0x33, "'": 0x34,
                              "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38,
                              "right": 0x4f, "left": 0x50, "down": 0x51, "up": 0x52]
    for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { k[String(c)] = 0x04 + UInt8(i) }
    for (i, c) in "1234567890".enumerated() { k[String(c)] = 0x1e + UInt8(i) }
    for n in 1...12 { k["f\(n)"] = 0x39 + UInt8(n) }
    for n in 13...24 { k["f\(n)"] = 0x5b + UInt8(n) }
    return k
}()

// "middle-click", "back", or a key combo such as "cmd+c" / "ctrl+up" / "f13".
func parseAction(_ s: String) -> (UInt8, UInt8, UInt8)? {
    if let a = namedActions[s] { return (a, 0, 0) }
    var parts = s.split(separator: "+").map(String.init)
    guard let key = parts.popLast().flatMap({ keyCodes[$0] }) else { return nil }
    var mods: UInt8 = 0
    for p in parts { guard let m = modifierBits[p] else { return nil }; mods |= m }
    return (0x11, mods, key)
}

func buttonReport(_ assignments: [String: (UInt8, UInt8, UInt8)]) -> [UInt8] {
    var p = [UInt8](repeating: 0, count: 59)
    p[0] = 0x08; p[1] = 0x3b; p[2] = 0x01
    for i in stride(from: 3, through: 54, by: 3) { p[i] = 0x01 } // unused slots: disabled
    let defaults: [String: UInt8] = ["left": 0x02, "right": 0x03, "middle": 0x04, "dpi": 0x0d,
                                     "forward": 0x06, "back": 0x05, "scroll-up": 0x09, "scroll-down": 0x0a]
    for (button, offset) in buttonOffsets {
        let (action, mods, key) = assignments[button] ?? (defaults[button]!, 0, 0)
        p[offset] = action; p[offset + 1] = mods; p[offset + 2] = key
    }
    p[58] = p[2..<58].reduce(0) { $0 &+ $1 } &- 1
    return p
}

func selfTest() {
    precondition(dpiCode(100) == 0x02 && dpiCode(800) == 0x12 && dpiCode(1600) == 0x25)
    precondition(dpiCode(10000) == 0xeb && dpiCode(10100) == 0x76 && dpiCode(18000) == 0xd3)
    precondition(dpiCode(50) == nil && dpiCode(850) == nil && dpiCode(18100) == nil)
    // Checksum must match the Rust driver's formula: 0x0d75 + codes + mid-band flags + 2*mask + (active-1) + options.
    let dpis = [800, 1600, 3200, 10100, 12000, 18000]
    let p = dpiReport(dpis, active: 3, angleSnap: true, ripple: false)!
    let rust = 0x0d75 + dpis.map { Int(dpiCode($0)!) }.reduce(0, +) + 2 + 2 * 0x20 + 2 + 1
    precondition(Int(p[50]) << 8 | Int(p[51]) == rust)
    precondition(pollingReport(1000)! == [0x06, 0x09, 0x01, 0x01, 0xfe, 0, 0, 0, 0] && pollingReport(300) == nil)
    precondition(sleepReport(seconds: 0.4, deepMinutes: 10, debounceMs: 4) == nil)
    // The R1 map only moves the DPI action from offset 18 to 12, so the X11 default checksum from the community driver's tests still holds.
    precondition(buttonReport([:])[58] == 0x3e && buttonReport([:])[12] == 0x0d)
    let copy = buttonReport(["left": parseAction("ctrl+c")!])
    precondition(Array(copy[3...5]) == [0x11, 0x01, 0x06])
    precondition(parseAction("cmd+shift+4")! == (0x11, 0x0a, 0x21) && parseAction("f13")! == (0x11, 0, 0x68))
    precondition(parseAction("ctrl+up")! == (0x11, 0x01, 0x52) && parseAction("hyper+x") == nil)
    precondition(parseAction("\\")! == (0x11, 0, 0x31) && parseAction("cmd+/")! == (0x11, 0x08, 0x38))
    print("selftest ok")
}

// MARK: - HID transport

struct R1Error: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// On Bluetooth the R1 shows up as "AttackSharkR1" (it borrows a Microsoft VID/PID). The dongle stays enumerated and
// even answers battery reads then, but writes sent through it never reach the mouse. Cheap: lists devices, opens none.
// Filtered by hand: a Product key in the matching dictionary is ignored and every HID device comes back.
func isOnBluetooth() -> Bool {
    let all = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(all, nil)
    return ((IOHIDManagerCopyDevices(all) as? Set<IOHIDDevice>) ?? []).contains { d in
        IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String == "AttackSharkR1" &&
            (IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "").contains("Bluetooth")
    }
}

// The R1 config interface is USB interface 2, which macOS exposes as Generic Desktop / System Control (0x80).
// Usage 0x02 (Mouse) is the pointer interface, used only to measure the real report rate.
func openMouse(usage: Int = 0x80) throws -> (IOHIDDevice, wired: Bool) {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matches = productIDs.map { pid in
        [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: pid,
         kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: usage] as CFDictionary
    }
    if isOnBluetooth() {
        throw R1Error(message: "the mouse is in Bluetooth mode, which has no configuration channel; switch it to 2.4G or plug the cable to configure (settings then apply on Bluetooth too)")
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = set.first else {
        throw R1Error(message: "Attack Shark R1 not found on the dongle or cable (1d57:fa60 / 1d57:fa61). Bluetooth mode has no configuration channel; settings saved via the dongle or cable still apply there.")
    }
    let rc = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard rc == kIOReturnSuccess else {
        throw R1Error(message: String(format: "could not open the mouse (IOReturn 0x%08x). If it is 0xe00002e2, allow your terminal under System Settings > Privacy & Security > Input Monitoring.", rc))
    }
    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
    return (device, pid == 0xfa61)
}

func send(_ device: IOHIDDevice, _ report: [UInt8]) throws {
    let rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(report[0]), report, report.count)
    guard rc == kIOReturnSuccess else {
        throw R1Error(message: String(format: "write of report 0x%02x failed (IOReturn 0x%08x). On the dongle, move the mouse to wake it and retry.", report[0], rc))
    }
    usleep(100_000) // the dongle relays over RF; give it time before the next write
}

var lastBattery: [UInt8]?

// Returns nil on the cable, which doesn't report a percentage. Runs the current thread's run loop while waiting.
func readBattery(_ device: IOHIDDevice, wired: Bool) throws -> (percent: Int, charging: Bool)? {
    if wired { return nil }
    lastBattery = nil
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    defer { buffer.deallocate() }
    IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { _, _, _, _, reportID, report, length in
        if reportID == 0x03 && length >= 5 { lastBattery = Array(UnsafeBufferPointer(start: report, count: length)) }
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    defer { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }
    let deadline = Date().addingTimeInterval(6)
    while lastBattery == nil && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.2, true) }
    guard let r = lastBattery else { throw R1Error(message: "no battery report within 6 s; move the mouse so it wakes up and retry") }
    let raw = r[4]
    let percent = raw <= 10 ? Int(raw) * 10 : min(Int(raw), 100) // firmware sends tenths or a percentage
    let charging = [0x02, 0x03, 0x80].contains(r[3]) || r.dropFirst(5).contains { $0 != 0 }
    return (percent, charging)
}
