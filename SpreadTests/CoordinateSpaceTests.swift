import CoreGraphics
import Testing
@testable import Spread

/// Simulated layout: primary 1920×1080 at the Cocoa origin, secondary 2560×1440 to its right,
/// raised 200 pt (Cocoa y grows upwards), so its top sits above the primary's top.
struct CoordinateSpaceTests {
    let primaryHeight: CGFloat = 1080
    let primaryCocoa = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let secondaryCocoa = CGRect(x: 1920, y: 200, width: 2560, height: 1440)

    @Test func primaryMapsOntoItself() {
        let ax = CoordinateSpace.axRect(primaryCocoa, primaryHeight: primaryHeight)
        #expect(ax == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test func tallerSecondaryHasNegativeAXY() {
        let ax = CoordinateSpace.axRect(secondaryCocoa, primaryHeight: primaryHeight)
        // Cocoa maxY = 1640, so the top edge is 560 pt above the primary's top.
        #expect(ax == CGRect(x: 1920, y: -560, width: 2560, height: 1440))
    }

    @Test func visibleFrameBelowMenuBar() {
        // Primary visible frame: 25 pt menu bar on top, 70 pt Dock at the bottom.
        let visible = CGRect(x: 0, y: 70, width: 1920, height: 1080 - 70 - 25)
        let ax = CoordinateSpace.axRect(visible, primaryHeight: primaryHeight)
        #expect(ax.minY == 25)
        #expect(ax.maxY == 1010) // 1080 − 70 pt Dock
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1920, y: 200, width: 2560, height: 1440),
        CGRect(x: 100.5, y: -300, width: 640, height: 480),
        CGRect(x: 2500, y: 1500, width: 800, height: 600),
    ])
    func roundTrip(rect: CGRect) {
        let ax = CoordinateSpace.axRect(rect, primaryHeight: primaryHeight)
        #expect(CoordinateSpace.cocoaRect(ax, primaryHeight: primaryHeight) == rect)
    }

    @Test func windowScreenAssignment() {
        let screens = [
            CoordinateSpace.axRect(primaryCocoa, primaryHeight: primaryHeight),
            CoordinateSpace.axRect(secondaryCocoa, primaryHeight: primaryHeight),
        ]
        // Mostly on the primary.
        #expect(CoordinateSpace.bestScreenIndex(for: CGRect(x: 1500, y: 100, width: 600, height: 400), among: screens) == 0)
        // Center on the secondary, straddling the edge.
        #expect(CoordinateSpace.bestScreenIndex(for: CGRect(x: 1800, y: 100, width: 600, height: 400), among: screens) == 1)
        // Entirely above the primary, on the secondary's raised part.
        #expect(CoordinateSpace.bestScreenIndex(for: CGRect(x: 2200, y: -500, width: 400, height: 300), among: screens) == 1)
        // Off every screen: falls back to the primary.
        #expect(CoordinateSpace.bestScreenIndex(for: CGRect(x: -5000, y: -5000, width: 10, height: 10), among: screens) == 0)
        #expect(CoordinateSpace.bestScreenIndex(for: .zero, among: []) == nil)
    }
}
