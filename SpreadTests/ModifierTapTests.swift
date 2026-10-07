import AppKit
import Testing
@testable import Spread

struct ModifierTapTests {
    let combo: NSEvent.ModifierFlags = [.control, .option, .command]

    /// Runs a sequence of events (nil = key or mouse event) and returns how often the tap fired.
    func fires(_ events: [NSEvent.ModifierFlags?]) -> Int {
        var state = ModifierTap.State.idle
        var count = 0
        for held in events {
            let result = ModifierTap.step(state, held: held, combination: combo)
            state = result.state
            if result.fire { count += 1 }
        }
        return count
    }

    @Test func cleanTapFires() {
        #expect(fires([[.control], [.control, .option], combo, [.option, .command], [.command], []]) == 1)
    }

    @Test func releasingAllAtOnceFires() {
        #expect(fires([combo, []]) == 1)
    }

    @Test func otherKeyWhileHeldCancels() {
        // ⌃⌥⌘T in Cursor must stay a Cursor shortcut.
        #expect(fires([combo, nil, [.control, .option], []]) == 0)
    }

    @Test func clickWhileHeldCancels() {
        #expect(fires([combo, nil, []]) == 0)
    }

    @Test func extraModifierCancels() {
        #expect(fires([combo, combo.union(.shift), combo, []]) == 0)
        #expect(fires([combo, combo.union(.shift), [.shift], []]) == 0)
        #expect(fires([[.shift], combo.union(.shift), combo, []]) == 0)
    }

    @Test func partialComboNeverFires() {
        #expect(fires([[.control], [.control, .option], [.control], []]) == 0)
        #expect(fires([[.control, .command], []]) == 0)
    }

    @Test func repeatedTapsFireEachTime() {
        #expect(fires([combo, [], combo, []]) == 2)
    }

    @Test func cancelEndsWhenEverythingIsReleased() {
        #expect(fires([combo, nil, [], combo, []]) == 1)
    }

    @Test func typingWithoutModifiersDoesNothing() {
        #expect(fires([nil, nil, [.shift], nil, []]) == 0)
    }
}
