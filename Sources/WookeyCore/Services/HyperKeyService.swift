import AppKit
import Carbon.HIToolbox
import CoreGraphics
import IOKit.hidsystem
import Observation

public enum HyperKeySource: String, CaseIterable, Sendable {
    case off
    case function
    case rightCommand
    case rightOption

    public var title: String {
        switch self {
        case .off: L10n.text("끔")
        case .function: "fn"
        case .rightCommand: L10n.text("오른쪽 ⌘")
        case .rightOption: L10n.text("오른쪽 ⌥")
        }
    }

    fileprivate var modifier: HyperModifier? {
        switch self {
        case .off: nil
        case .function: .function
        case .rightCommand: .rightCommand
        case .rightOption: .rightOption
        }
    }
}

struct HyperModifier {
    let keyCode: CGKeyCode
    let aggregate: CGEventFlags
    let side: CGEventFlags
    let opposite: CGEventFlags

    var flags: CGEventFlags { aggregate.union(side) }

    func isDown(in flags: CGEventFlags) -> Bool {
        return (!side.isEmpty && flags.contains(side))
            || (flags.contains(aggregate) && flags.intersection(opposite).isEmpty)
    }

    func removing(from flags: CGEventFlags) -> CGEventFlags {
        let withoutSide = flags.subtracting(side)
        return flags.intersection(opposite).isEmpty ? withoutSide.subtracting(aggregate) : withoutSide
    }

    static let function = Self(
        keyCode: CGKeyCode(kVK_Function), aggregate: .maskSecondaryFn, side: [], opposite: []
    )
    static let rightCommand = Self(
        keyCode: CGKeyCode(kVK_RightCommand), aggregate: .maskCommand,
        side: CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK)),
        opposite: CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
    )
    static let rightOption = Self(
        keyCode: CGKeyCode(kVK_RightOption), aggregate: .maskAlternate,
        side: CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK)),
        opposite: CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
    )
    static let leftControl = Self(
        keyCode: CGKeyCode(kVK_Control), aggregate: .maskControl,
        side: CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK)),
        opposite: CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK))
    )
    static let leftOption = Self(
        keyCode: CGKeyCode(kVK_Option), aggregate: .maskAlternate,
        side: CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK)),
        opposite: CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
    )
    static let leftShift = Self(
        keyCode: CGKeyCode(kVK_Shift), aggregate: .maskShift,
        side: CGEventFlags(rawValue: UInt64(NX_DEVICELSHIFTKEYMASK)),
        opposite: CGEventFlags(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))
    )
}

struct HyperKeyState {
    struct Change: Equatable {
        let keyCode: CGKeyCode
        let isDown: Bool
        let flags: CGEventFlags
    }

    struct Result: Equatable {
        // Nil consumes the original input event after delivering the changes.
        let flags: CGEventFlags?
        var changes: [Change] = []
    }

    static let output: [HyperModifier] = [.leftControl, .leftOption, .leftShift]
    static let outputFlags = output.reduce(into: CGEventFlags()) { $0.formUnion($1.flags) }

    let source: HyperKeySource
    private(set) var isHeld = false

    init(source: HyperKeySource) {
        self.source = source
    }

    mutating func handle(type: CGEventType, keyCode: CGKeyCode?, flags: CGEventFlags) -> Result {
        guard let modifier = source.modifier else { return Result(flags: flags) }

        if keyCode == modifier.keyCode {
            let isDown = type == .flagsChanged ? modifier.isDown(in: flags) : type == .keyDown
            guard isDown != isHeld else { return Result(flags: nil) }
            isHeld = isDown
            let physical = modifier.removing(from: flags)
            return Result(flags: nil, changes: Self.changes(isDown: isDown, physical: physical))
        }

        guard isHeld else { return Result(flags: flags) }
        // The system can withhold modifier events while secure input is active.
        // Reconcile at the next physical keyboard or pointer event.
        guard modifier.isDown(in: flags) else {
            return Result(flags: flags, changes: release(physical: flags))
        }
        if type == .flagsChanged, Self.output.contains(where: { $0.keyCode == keyCode }) {
            return Result(flags: nil)
        }
        return Result(flags: modifier.removing(from: flags).union(Self.outputFlags))
    }

    mutating func reset(physical: CGEventFlags) -> [Change] {
        release(physical: source.modifier?.removing(from: physical) ?? physical)
    }

    private mutating func release(physical: CGEventFlags) -> [Change] {
        guard isHeld else { return [] }
        isHeld = false
        return Self.changes(isDown: false, physical: physical)
    }

    private static func changes(isDown: Bool, physical: CGEventFlags) -> [Change] {
        let order = isDown ? Self.output : Array(Self.output.reversed())
        var virtual = isDown ? CGEventFlags() : Self.outputFlags
        return order.compactMap { modifier in
            if isDown { virtual.formUnion(modifier.flags) }
            else { virtual.subtract(modifier.flags) }
            guard !modifier.isDown(in: physical) else { return nil }
            return Change(keyCode: modifier.keyCode, isDown: isDown, flags: physical.union(virtual))
        }
    }
}

@MainActor
@Observable
public final class HyperKeyService {
    public enum Status { case off, permissionRequired, active, unavailable }

    public private(set) var source: HyperKeySource
    public private(set) var status: Status = .off
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tap = HyperKeyTap()
    private static let storageKey = "hyperKeySource"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        source = defaults.string(forKey: Self.storageKey).flatMap(HyperKeySource.init(rawValue:)) ?? .off
    }

    public func setSource(_ source: HyperKeySource) {
        guard source != self.source else { return }
        tap.stop()
        self.source = source
        defaults.set(source.rawValue, forKey: Self.storageKey)
        refresh()
    }

    func refresh() {
        guard source != .off else {
            status = .off
            return
        }
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
            tap.stop()
            status = .permissionRequired
            return
        }
        status = tap.start(source: source) ? .active : .unavailable
    }

    public func stop() {
        tap.stop()
        status = .off
    }
}

/// The callback and all lifecycle operations run on the main run loop.
private final class HyperKeyTap {
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var state = HyperKeyState(source: .off)
    private let eventSource = CGEventSource(stateID: .privateState)
    private static let syntheticEventUserData: Int64 = 0x574F4F4B485950
    private static let keyboardEvents: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
    private static let pointerEvents: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ]

    deinit {
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
        if let port { CFMachPortInvalidate(port) }
    }

    func start(source: HyperKeySource) -> Bool {
        if let port, CFMachPortIsValid(port) { return true }
        stop()
        guard eventSource != nil else { return false }
        let mask = (Self.keyboardEvents + Self.pointerEvents).reduce(into: CGEventMask(0)) {
            $0 |= CGEventMask(1) << $1.rawValue
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<HyperKeyTap>.fromOpaque(context).takeUnretainedValue()
                    .receive(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        state = HyperKeyState(source: source)
        self.port = port
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
        if let port { CFMachPortInvalidate(port) }
        runLoopSource = nil
        port = nil
        releaseModifiers()
    }

    private func receive(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseModifiers()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != Self.syntheticEventUserData, marker != KeyboardService.syntheticEventUserData else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Self.keyboardEvents.contains(type)
            ? CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)) : nil
        let result = state.handle(type: type, keyCode: keyCode, flags: event.flags)
        for change in result.changes {
            makeEvent(for: change)?.tapPostEvent(proxy)
        }
        guard let flags = result.flags else { return nil }
        if flags != event.flags { event.flags = flags }
        return Unmanaged.passUnretained(event)
    }

    private func releaseModifiers() {
        for change in state.reset(physical: CGEventSource.flagsState(.hidSystemState)) {
            makeEvent(for: change)?.post(tap: .cgSessionEventTap)
        }
    }

    private func makeEvent(for change: HyperKeyState.Change) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: change.keyCode, keyDown: change.isDown)
        else { return nil }
        event.type = .flagsChanged
        event.flags = change.flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventUserData)
        return event
    }
}
