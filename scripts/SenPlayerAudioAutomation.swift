import AppKit
import CoreAudio
import Foundation

private let senPlayerBundleID = "com.wuziqi.SenPlayer"
private let delayKey = "kGlobalAudioDelay"
private let defaultAirPlayDelay = -2.0
private let defaultLocalDelay = 0.0

private struct AudioDeviceInfo: Codable {
    let id: UInt32
    let name: String
    let uid: String
    let transport: String
    let isDefaultOutput: Bool
    let isAirPlay: Bool
}

private struct Options {
    var airPlayDelay = defaultAirPlayDelay
    var localDelay = defaultLocalDelay
    var listDevices = false
    var applyOnce = false
    var force = false
    var showHelp = false
}

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private func usage() {
    print("""
    Usage: SenPlayerAudioAutomation [options]
      --airplay-delay SECONDS  SenPlayer compensation for AirPlay (default: -2.0)
      --local-delay SECONDS    SenPlayer compensation for non-AirPlay (default: 0.0)
      --list                   Print CoreAudio devices as JSON and exit
      --once                   Apply the current-output rule once and exit
      --force                  Apply even if the stored value already matches
      --help                   Show this help

    With no mode option, the process watches the default output continuously.
    """)
}

private func parseOptions() -> Options {
    var options = Options()
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func value(after flag: String) -> Double {
        guard index + 1 < arguments.count, let value = Double(arguments[index + 1]) else {
            fputs("Invalid or missing numeric value for \(flag)\n", stderr)
            exit(64)
        }
        index += 1
        return value
    }

    while index < arguments.count {
        switch arguments[index] {
        case "--airplay-delay":
            options.airPlayDelay = value(after: "--airplay-delay")
        case "--local-delay":
            options.localDelay = value(after: "--local-delay")
        case "--list":
            options.listDevices = true
        case "--once":
            options.applyOnce = true
        case "--force":
            options.force = true
        case "--help", "-h":
            options.showHelp = true
        default:
            fputs("Unknown option: \(arguments[index])\n", stderr)
            usage()
            exit(64)
        }
        index += 1
    }
    return options
}

private func fourCC(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
    return String(bytes: bytes.map { (32...126).contains($0) ? $0 : 46 }, encoding: .ascii) ?? "...."
}

private func propertyUInt32(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> UInt32? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

private func propertyString(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
    guard status == noErr, let value else { return nil }
    return value.takeUnretainedValue() as String
}

private func defaultOutputDeviceID() -> AudioDeviceID? {
    propertyUInt32(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice
    )
}

private func allAudioDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size
    ) == noErr else {
        return []
    }

    var devices = [AudioDeviceID](
        repeating: 0,
        count: Int(size) / MemoryLayout<AudioDeviceID>.size
    )
    let status = devices.withUnsafeMutableBytes { buffer in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            buffer.baseAddress!
        )
    }
    return status == noErr ? devices : []
}

private func deviceInfo(_ deviceID: AudioDeviceID, defaultID: AudioDeviceID?) -> AudioDeviceInfo {
    let name = propertyString(
        objectID: deviceID,
        selector: kAudioObjectPropertyName
    ) ?? "Unknown"
    let uid = propertyString(
        objectID: deviceID,
        selector: kAudioDevicePropertyDeviceUID
    ) ?? ""
    let transportValue = propertyUInt32(
        objectID: deviceID,
        selector: kAudioDevicePropertyTransportType
    ) ?? 0
    let normalizedName = name.lowercased()
    let normalizedUID = uid.lowercased()
    let isAirPlay = transportValue == kAudioDeviceTransportTypeAirPlay
        || normalizedName.contains("airplay")
        || normalizedName.contains("airport")
        || normalizedUID.contains("airplay")
        || normalizedUID.contains("airport")

    return AudioDeviceInfo(
        id: deviceID,
        name: name,
        uid: uid,
        transport: fourCC(transportValue),
        isDefaultOutput: deviceID == defaultID,
        isAirPlay: isAirPlay
    )
}

private func preferenceDomainPath() -> String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.wuziqi.SenPlayer/Data/Library/Preferences/com.wuziqi.SenPlayer")
        .path
}

@discardableResult
private func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    } catch {
        return (1, error.localizedDescription)
    }
}

private func currentDelay() -> Double? {
    let result = runProcess("/usr/bin/defaults", ["read", preferenceDomainPath(), delayKey])
    guard result.status == 0 else { return nil }
    return Double(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func setDelay(_ delay: Double) -> Bool {
    let result = runProcess(
        "/usr/bin/defaults",
        ["write", preferenceDomainPath(), delayKey, "-float", String(delay)]
    )
    if result.status != 0 {
        log("Failed to write SenPlayer delay: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return result.status == 0
}

private func restartSenPlayerIfRunning(then action: () -> Bool) {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: senPlayerBundleID)
    let wasRunning = !runningApps.isEmpty

    if wasRunning {
        log("Requesting SenPlayer to quit before applying the new delay")
        runningApps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              !NSRunningApplication.runningApplications(withBundleIdentifier: senPlayerBundleID).isEmpty {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: senPlayerBundleID).isEmpty else {
            log("SenPlayer did not quit within 5 seconds; skipped the delay change")
            return
        }
    }

    guard action() else { return }

    if wasRunning {
        Thread.sleep(forTimeInterval: 0.2)
        let openResult = runProcess("/usr/bin/open", ["-b", senPlayerBundleID])
        if openResult.status == 0 {
            log("Reopened SenPlayer")
        } else {
            log("Failed to reopen SenPlayer: \(openResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

private func applyForCurrentOutput(options: Options, force: Bool = false) {
    guard let defaultID = defaultOutputDeviceID() else {
        log("No default output device is available")
        return
    }
    let info = deviceInfo(defaultID, defaultID: defaultID)
    let targetDelay = info.isAirPlay ? options.airPlayDelay : options.localDelay
    let oldDelay = currentDelay()

    if !force, let oldDelay, abs(oldDelay - targetDelay) < 0.001 {
        log("No change: \(info.name) already uses delay \(targetDelay)")
        return
    }

    restartSenPlayerIfRunning {
        guard setDelay(targetDelay) else { return false }
        log("Applied delay \(targetDelay) for output \(info.name) [\(info.transport)]")
        return true
    }
}

private func printDevices() {
    let defaultID = defaultOutputDeviceID()
    let devices = allAudioDeviceIDs().map { deviceInfo($0, defaultID: defaultID) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(devices) else { return }
    print(String(decoding: data, as: UTF8.self))
}

private final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let options: Options

    init(options: Options) {
        self.options = options
    }

    func schedule() {
        workItem?.cancel()
        let item = DispatchWorkItem {
            applyForCurrentOutput(options: self.options)
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}

private func watchDefaultOutput(options: Options) -> Never {
    log("Process started; AirPlay delay \(options.airPlayDelay), local delay \(options.localDelay)")
    let debouncer = Debouncer(options: options)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        DispatchQueue.main
    ) { _, _ in
        debouncer.schedule()
    }
    guard status == noErr else {
        fatalError("Unable to monitor the default audio output (OSStatus \(status))")
    }

    applyForCurrentOutput(options: options)
    log("Watching default audio output changes")
    dispatchMain()
}

private let options = parseOptions()
if options.showHelp {
    usage()
} else if options.listDevices {
    printDevices()
} else if options.applyOnce {
    applyForCurrentOutput(options: options, force: options.force)
} else {
    watchDefaultOutput(options: options)
}
