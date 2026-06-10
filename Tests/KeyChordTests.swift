import XCTest
import Carbon.HIToolbox
@testable import GlossPop

final class KeyChordTests: XCTestCase {
    func testCarbonModifiersMapping() {
        XCTAssertEqual(KeyChord.carbonModifiers([.control, .command]), UInt32(controlKey | cmdKey))
        XCTAssertEqual(KeyChord.carbonModifiers([.option, .shift]), UInt32(optionKey | shiftKey))
    }

    func testSymbolsOrder() {
        XCTAssertEqual(KeyChord.symbols(carbon: UInt32(controlKey | cmdKey)), "⌃⌘")
        XCTAssertEqual(KeyChord.symbols(carbon: UInt32(optionKey | shiftKey | cmdKey)), "⌥⇧⌘")
    }

    private func event(_ mods: NSEvent.ModifierFlags, _ ch: String, _ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
                         windowNumber: 0, context: nil, characters: ch,
                         charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
    }

    func testCandidateRejectsBareCommandOrShift() {
        // ⌘C and ⇧A must NOT be accepted as a global hotkey (no Control/Option).
        XCTAssertNil(KeyChord.candidate(from: event([.command], "c", 8)))
        XCTAssertNil(KeyChord.candidate(from: event([.shift], "a", 0)))
        XCTAssertNil(KeyChord.candidate(from: event([.command, .shift], "s", 1)))
    }

    func testCandidateAcceptsControlOrOption() {
        let c = KeyChord.candidate(from: event([.control, .command], "t", UInt16(kVK_ANSI_T)))
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.displayKey, "T")
        XCTAssertNotNil(KeyChord.candidate(from: event([.option, .command], "space", UInt16(kVK_Space))))
    }
}
