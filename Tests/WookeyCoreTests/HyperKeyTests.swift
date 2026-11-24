import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import WookeyCore

struct HyperKeyTests {
    @Test(arguments: [HyperKeySource.function, .rightCommand, .rightOption])
    func pressAndReleaseSendLeftModifiers(source: HyperKeySource) {
        let input: HyperModifier = switch source {
        case .function: .function
        case .rightCommand: .rightCommand
        case .rightOption: .rightOption
        case .off: fatalError("Test requires a source key")
        }
        var state = HyperKeyState(source: source)
        let press = state.handle(type: .flagsChanged, keyCode: input.keyCode, flags: input.flags)
        #expect(press.flags == nil)
        #expect(press.changes.map(\.keyCode) == HyperKeyState.output.map(\.keyCode))
        #expect(press.changes.allSatisfy { $0.isDown })
        #expect(press.changes.last?.flags == HyperKeyState.outputFlags)

        let chord = state.handle(type: .keyDown, keyCode: CGKeyCode(kVK_ANSI_A), flags: input.flags)
        #expect(chord.flags == HyperKeyState.outputFlags)
        #expect(chord.changes.isEmpty)
        let repeatEvent = state.handle(type: .keyDown, keyCode: input.keyCode, flags: input.flags)
        #expect(repeatEvent.flags == nil && repeatEvent.changes.isEmpty)

        let release = state.handle(type: .flagsChanged, keyCode: input.keyCode, flags: [])
        #expect(release.flags == nil)
        #expect(release.changes.map(\.keyCode) == Array(HyperKeyState.output.reversed().map(\.keyCode)))
        #expect(release.changes.allSatisfy { !$0.isDown })
        #expect(release.changes.last?.flags == [])
        #expect(!state.isHeld)
    }

    @Test func oppositeCommandAndPointerFlagsArePreserved() {
        let source = HyperModifier.rightCommand
        let leftCommand = source.aggregate.union(source.opposite)
        let physical = source.flags.union(leftCommand).union(.maskAlphaShift)
        var state = HyperKeyState(source: .rightCommand)
        _ = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: physical)
        let click = state.handle(type: .leftMouseDown, keyCode: nil, flags: physical)
        #expect(click.flags == leftCommand.union(.maskAlphaShift).union(HyperKeyState.outputFlags))
        let release = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: leftCommand)
        #expect(release.changes.last?.flags == leftCommand)
    }

    @Test func alreadyHeldLeftOptionIsNotDuplicatedOrReleased() {
        let source = HyperModifier.rightOption
        let left = HyperModifier.leftOption
        var state = HyperKeyState(source: .rightOption)
        let press = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: source.flags.union(left.flags))
        #expect(!press.changes.contains { $0.keyCode == left.keyCode })
        let release = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: left.flags)
        #expect(!release.changes.contains { $0.keyCode == left.keyCode })
        #expect(release.changes.last?.flags == left.flags)
    }

    @Test func physicalShiftChangesAreCoveredUntilHyperReleases() {
        let source = HyperModifier.function
        let shift = HyperModifier.leftShift
        var state = HyperKeyState(source: .function)
        _ = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: source.flags.union(shift.flags))
        let physicalRelease = state.handle(type: .flagsChanged, keyCode: shift.keyCode, flags: source.flags)
        #expect(physicalRelease.flags == nil && physicalRelease.changes.isEmpty)
        let release = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: [])
        #expect(release.changes.first?.keyCode == shift.keyCode)
        #expect(release.changes.last?.flags == [])
    }

    @Test func missedReleaseAndResetBothClearVirtualModifiers() {
        let source = HyperModifier.function
        var state = HyperKeyState(source: .function)
        _ = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: source.flags)
        let reconciled = state.handle(type: .keyDown, keyCode: CGKeyCode(kVK_ANSI_A), flags: [])
        #expect(reconciled.flags == [] && reconciled.changes.count == 3)
        #expect(!state.isHeld)

        _ = state.handle(type: .flagsChanged, keyCode: source.keyCode, flags: source.flags)
        #expect(state.reset(physical: source.flags).last?.flags == [])
        #expect(state.reset(physical: []).isEmpty)
    }

    @Test func offAndUnselectedKeysPassThrough() {
        let input = HyperModifier.rightCommand
        for source in [HyperKeySource.off, .rightOption] {
            var state = HyperKeyState(source: source)
            let result = state.handle(type: .flagsChanged, keyCode: input.keyCode, flags: input.flags)
            #expect(result.flags == input.flags && result.changes.isEmpty)
        }
    }

    @MainActor
    @Test func remembersSourceInDevicePreferences() throws {
        let name = "HyperKeyTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let service = HyperKeyService(defaults: defaults)
        #expect(service.source == .off)
        // Seed the same value persisted by the settings change without starting an event tap in a test process.
        defaults.set(HyperKeySource.rightOption.rawValue, forKey: "hyperKeySource")
        #expect(HyperKeyService(defaults: defaults).source == .rightOption)
    }
}
