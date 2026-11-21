import Cocoa
import IOKit.ps

// MARK: - Stats

var prev = host_cpu_load_info()
var havePrev = false

func cpu() -> Double {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard r == KERN_SUCCESS else { return 0 }
    defer { prev = info; havePrev = true }
    guard havePrev else { return 0 }
    let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
    let p = [prev.cpu_ticks.0, prev.cpu_ticks.1, prev.cpu_ticks.2, prev.cpu_ticks.3]
    let diff = zip(t, p).map { Double($0 &- $1) }
    let total = diff.reduce(0, +)
    return total > 0 ? (total - diff[Int(CPU_STATE_IDLE)]) / total * 100 : 0
}

struct Mem { var app = 0.0, wired = 0.0, compressed = 0.0, cached = 0.0, free = 0.0, total = 0.0
    var used: Double { app + wired + compressed }
    var pct: Double { used / total * 100 } }

func mem() -> Mem {
    var s = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &s) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    guard r == KERN_SUCCESS else { return Mem(total: 1) }
    let gb = Double(vm_page_size) / 1_073_741_824
    return Mem(app: (Double(s.internal_page_count) - Double(s.purgeable_count)) * gb,
               wired: Double(s.wire_count) * gb,
               compressed: Double(s.compressor_page_count) * gb,
               cached: (Double(s.external_page_count) + Double(s.purgeable_count)) * gb,
               free: Double(s.free_count) * gb,
               total: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
}

// 1 = normal, 2 = warning, 4 = critical. This, not "% used", is what says whether RAM is a problem.
func pressure() -> Int {
    var v: Int32 = 1; var size = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &v, &size, nil, 0)
    return Int(v)
}

func disk() -> (used: Double, free: Double, total: Double) {
    let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    let total = Double(v?.volumeTotalCapacity ?? 1) / 1e9
    let free = Double(v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1e9
    return (total - free, free, total)
}

func level(_ pct: Double, warn: Double, bad: Double) -> NSColor {
    pct < warn ? .systemGreen : pct < bad ? .systemOrange : .systemRed
}

struct Battery { var pct = 0.0, charging = false, onAC = false, minutes = -1, watts = 0.0 }

// nil on Macs without a battery. minutes = time to empty (on battery) or to full (charging), -1 if macOS is still estimating.
func battery() -> Battery? {
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    guard let src = (IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]).first,
          let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any] else { return nil }
    var b = Battery()
    b.pct = Double(d[kIOPSCurrentCapacityKey] as? Int ?? 0)
    b.charging = d[kIOPSIsChargingKey] as? Bool ?? false
    b.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    if b.charging { b.minutes = d[kIOPSTimeToFullChargeKey] as? Int ?? -1 }
    else if !b.onAC { let t = IOPSGetTimeRemainingEstimate(); b.minutes = t > 0 ? Int(t / 60) : -1 }
    // Live draw from the battery gauge: milliamps (negative = discharging) x millivolts.
    var props: Unmanaged<CFMutableDictionary>?
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if svc != 0, IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
       let p = props?.takeRetainedValue() as? [String: Any],
       let mA = (p["InstantAmperage"] as? NSNumber)?.int64Value, let mV = (p["Voltage"] as? NSNumber)?.doubleValue {
        b.watts = abs(Double(mA) * mV) / 1e6
    }
    IOObjectRelease(svc)
    return b
}

func hm(_ m: Int) -> String { m < 0 ? "calculating…" : "\(m / 60)h \(m % 60)m" }

// Top processes via ps; only runs when a menu is opened.
func topProcesses(byMemory: Bool) -> [(pid: Int32, name: String, cpu: String, rss: Double)] {
    let p = Process(); let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-Aco", "pid=,pcpu=,rss=,comm=", byMemory ? "-m" : "-r"]
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return [] }
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return out.split(separator: "\n").prefix(8).compactMap { line in
        let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard f.count == 4, let pid = Int32(f[0]), let kb = Double(f[2]) else { return nil }
        return (pid, String(f[3]), String(f[1]), kb / 1_048_576)
    }
}

// MARK: - Rendering

func render(_ label: String, _ pct: Double, _ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 38, height: 22), flipped: false) { _ in
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), .foregroundColor: NSColor.labelColor]
        label.draw(at: NSPoint(x: 0, y: 11), withAttributes: small)
        String(format: "%.0f%%", pct).draw(at: NSPoint(x: 0, y: 0), withAttributes: big)
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: NSRect(x: 30, y: 3, width: 6, height: 16), xRadius: 1.5, yRadius: 1.5).fill()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 30, y: 3, width: 6, height: max(2, 16 * min(pct, 100) / 100)), xRadius: 1.5, yRadius: 1.5).fill()
        return true
    }
}

// MARK: - Menus

enum Kind { case cpu, ram, disk, battery }

final class Meter: NSObject, NSMenuDelegate {
    let kind: Kind
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(_ kind: Kind) {
        self.kind = kind
        super.init()
        item.menu = NSMenu()
        item.menu?.delegate = self
    }

    func show(_ label: String, _ pct: Double, _ color: NSColor) {
        item.button?.image = render(label, pct, color)
    }

    @objc func noop() {}

    @objc func kill(_ sender: NSMenuItem) {
        Darwin.kill(Int32(sender.tag), sender.representedObject as? Int32 ?? SIGTERM)
    }

    func text(_ menu: NSMenu, _ s: String, bold: Bool = false, mono: Bool = false) {
        let i = NSMenuItem(title: s, action: #selector(noop), keyEquivalent: "")
        i.target = self
        if bold { i.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
        if mono { i.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]) }
        menu.addItem(i)
    }

    // Monospaced so the numbers line up.
    func row(_ menu: NSMenu, _ label: String, _ gb: Double, _ note: String = "") {
        text(menu, label.padding(toLength: 15, withPad: " ", startingAt: 0) + String(format: "%5.1f GB", gb) + note, mono: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch kind {
        case .ram:
            let m = mem(), pr = pressure()
            text(menu, String(format: "Memory: %.1f of %.0f GB in use", m.used, m.total), bold: true)
            text(menu, pr == 1 ? "✅ Healthy: macOS is just using spare RAM" : pr == 2 ? "⚠️ Getting tight: consider closing apps" : "🔴 Under pressure: close some apps")
            menu.addItem(.separator())
            row(menu, "Apps", m.app)
            row(menu, "Wired (system)", m.wired)
            row(menu, "Compressed", m.compressed)
            menu.addItem(.separator())
            row(menu, "Cached files", m.cached, "  (freed on demand)")
            row(menu, "Free", m.free)
        case .cpu:
            text(menu, String(format: "CPU: %.0f%% busy", cpuNow), bold: true)
        case .battery:
            guard let b = battery() else { break }
            text(menu, String(format: "Battery: %.0f%%", b.pct), bold: true)
            if b.charging { text(menu, "⚡ Charging, full in \(hm(b.minutes))") }
            else if b.onAC { text(menu, "🔌 On power, not charging") }
            else { text(menu, "🔋 About \(hm(b.minutes)) left at current use") }
            text(menu, String(format: "%@ %.1f W", b.onAC ? "Charging at" : "Drawing", b.watts))
        case .disk:
            let d = disk()
            text(menu, String(format: "Disk: %.0f of %.0f GB used", d.used, d.total), bold: true)
            text(menu, String(format: "%.0f GB available", d.free))
        }
        if kind == .cpu || kind == .ram {
            menu.addItem(.separator())
            text(menu, kind == .cpu ? "Top apps by CPU (click to quit)" : "Top apps by memory (click to quit)", bold: true)
            for p in topProcesses(byMemory: kind == .ram) {
                let detail = kind == .ram ? String(format: "%.1f GB", p.rss) : "\(p.cpu)%"
                let row = NSMenuItem(title: "\(p.name)  —  \(detail)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for (title, sig) in [("Quit", SIGTERM), ("Force Quit", SIGKILL)] {
                    let a = NSMenuItem(title: title, action: #selector(kill(_:)), keyEquivalent: "")
                    a.target = self; a.tag = Int(p.pid); a.representedObject = sig
                    sub.addItem(a)
                }
                row.submenu = sub
                menu.addItem(row)
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tidemark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

// Status items appear right-to-left in creation order.
let batMeter = Meter(.battery), diskMeter = Meter(.disk), ramMeter = Meter(.ram), cpuMeter = Meter(.cpu)
var cpuNow = 0.0

func update() {
    cpuNow = cpu()
    cpuMeter.show("CPU", cpuNow, level(cpuNow, warn: 60, bad: 85))
    let m = mem(), pr = pressure()
    ramMeter.show("RAM", m.pct, pr == 1 ? .systemGreen : pr == 2 ? .systemOrange : .systemRed)
    if let b = battery() {
        batMeter.show(b.charging ? "CHG" : "BAT", b.pct, b.pct <= 10 ? .systemRed : b.pct <= 20 ? .systemOrange : .systemGreen)
    } else { batMeter.item.isVisible = false }
    let d = disk()
    diskMeter.show("SSD", d.used / d.total * 100, level(d.used / d.total * 100, warn: 80, bad: 92))
}

_ = cpu()
update()
let timer = Timer(timeInterval: 3, repeats: true) { _ in update() }
timer.tolerance = 1
RunLoop.main.add(timer, forMode: .common)

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
