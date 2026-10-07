import CoreGraphics
import Testing
@testable import Spread

struct GridLayoutTests {
    static let aspects: [(name: String, size: CGSize)] = [
        ("16:9", CGSize(width: 1920, height: 1080)),
        ("21:9", CGSize(width: 3440, height: 1440)),
        ("32:9", CGSize(width: 5120, height: 1440)),
        ("9:16", CGSize(width: 1080, height: 1920)),
    ]
    static let gaps: [CGFloat] = [0, 8, 24]

    /// A non-zero origin, like a secondary display's visible frame below the menu bar.
    static func bounds(_ size: CGSize) -> CGRect {
        CGRect(origin: CGPoint(x: 1920, y: 25), size: size)
    }

    // MARK: Invariants

    @Test(arguments: 1...12)
    func invariants(n: Int) {
        for (name, size) in Self.aspects {
            for gap in Self.gaps {
                let bounds = Self.bounds(size)
                let frames = GridLayout.frames(count: n, in: bounds, gap: gap)
                let context = "n=\(n) \(name) gap=\(gap)"

                #expect(frames.count == n, "\(context): count")

                let inner = bounds.insetBy(dx: gap, dy: gap)
                for frame in frames {
                    #expect(inner.contains(frame), "\(context): \(frame) outside \(inner)")
                    #expect(frame.width > 0 && frame.height > 0, "\(context): empty frame")
                }

                for i in frames.indices {
                    for j in frames.indices where j > i {
                        let overlap = frames[i].intersection(frames[j])
                        #expect(overlap.isNull || overlap.width * overlap.height == 0,
                                "\(context): \(frames[i]) overlaps \(frames[j])")
                    }
                }

                let rows = Self.rows(frames)
                for row in rows {
                    #expect(row.first?.minX == inner.minX, "\(context): row starts at left edge")
                    #expect(row.last?.maxX == inner.maxX, "\(context): row ends at right edge")
                    for (a, b) in zip(row, row.dropFirst()) {
                        #expect(abs(b.minX - a.maxX - gap) <= 1, "\(context): gap between columns")
                    }
                }
                #expect(rows.first?.first?.minY == inner.minY, "\(context): top edge")
                #expect(rows.last?.first?.maxY == inner.maxY, "\(context): bottom edge")

                let heights = frames.map(\.height)
                #expect(heights.max()! - heights.min()! <= 1, "\(context): equal heights")

                // Reading order: rows top to bottom, left to right inside a row.
                for (a, b) in zip(frames, frames.dropFirst()) {
                    #expect(a.minY < b.minY || (a.minY == b.minY && a.minX < b.minX), "\(context): reading order")
                }

                // Every row is full except possibly the last, which has at least one cell.
                let counts = rows.map(\.count)
                #expect(counts.dropLast().allSatisfy { $0 == counts[0] }, "\(context): full rows")
                #expect(counts.last! <= counts[0], "\(context): last row not wider than the others")
            }
        }
    }

    @Test func emptyAndInvalidInput() {
        #expect(GridLayout.frames(count: 0, in: Self.bounds(CGSize(width: 1920, height: 1080)), gap: 8).isEmpty)
        #expect(GridLayout.frames(count: -3, in: Self.bounds(CGSize(width: 1920, height: 1080)), gap: 8).isEmpty)
        #expect(GridLayout.frames(count: 3, in: .zero, gap: 8).isEmpty)
    }

    // MARK: Pinned shapes

    @Test(arguments: [
        (1, [1]), (2, [2]), (3, [3]), (4, [2, 2]), (5, [3, 2]), (6, [3, 3]),
        (7, [4, 3]), (8, [4, 4]), (9, [3, 3, 3]), (10, [5, 5]), (11, [4, 4, 3]), (12, [4, 4, 4]),
    ])
    func shapes16x9(n: Int, expected: [Int]) {
        for gap in Self.gaps {
            let counts = GridLayout.rowCounts(count: n, in: Self.bounds(CGSize(width: 1920, height: 1080)), gap: gap)
            #expect(counts == expected, "gap=\(gap)")
        }
    }

    @Test func fiveWindowsBottomRowIsWider() {
        let frames = GridLayout.frames(count: 5, in: Self.bounds(CGSize(width: 1920, height: 1080)), gap: 8)
        #expect(frames[3].width > frames[0].width)
        #expect(frames[3].minY > frames[0].minY)
    }

    @Test func portraitStacksThree() {
        let counts = GridLayout.rowCounts(count: 3, in: Self.bounds(CGSize(width: 1080, height: 1920)), gap: 8)
        #expect(counts == [1, 1, 1])
    }

    /// Wide screens prefer more columns. (4 windows on 3440×1440 is a near tie between 2×2 and
    /// four columns, about 0.698 each, so it is deliberately not pinned.)
    @Test func ultrawide() {
        let wide = Self.bounds(CGSize(width: 3440, height: 1440))
        #expect(GridLayout.rowCounts(count: 2, in: wide, gap: 8) == [2])
        #expect(GridLayout.rowCounts(count: 3, in: wide, gap: 8) == [3])
        #expect(GridLayout.rowCounts(count: 6, in: wide, gap: 8) == [3, 3])

        let superWide = Self.bounds(CGSize(width: 5120, height: 1440))
        #expect(GridLayout.rowCounts(count: 3, in: superWide, gap: 8) == [3])
        #expect(GridLayout.rowCounts(count: 4, in: superWide, gap: 8) == [4])
    }

    @Test func singleWindowFillsInsetBounds() {
        let bounds = Self.bounds(CGSize(width: 1920, height: 1080))
        #expect(GridLayout.frames(count: 1, in: bounds, gap: 8) == [bounds.insetBy(dx: 8, dy: 8)])
    }

    // MARK: Helpers

    static func rows(_ frames: [CGRect]) -> [[CGRect]] {
        Dictionary(grouping: frames, by: \.minY)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.minX < $1.minX } }
    }
}

struct ScreenSplitTests {
    // Usable areas of the LG (2560×1415) and the built-in display (1728×1085).
    let lg: CGFloat = 2560 * 1415
    let laptop: CGFloat = 1728 * 1085

    @Test(arguments: 0...12)
    func countsAddUp(n: Int) {
        let counts = GridLayout.split(count: n, weights: [laptop, lg])
        #expect(counts.reduce(0, +) == n)
        #expect(counts.allSatisfy { $0 >= 0 })
        // The bigger screen never gets fewer windows.
        #expect(counts[1] >= counts[0])
    }

    @Test func proportionalToArea() {
        #expect(GridLayout.split(count: 5, weights: [laptop, lg]) == [2, 3])
        #expect(GridLayout.split(count: 2, weights: [laptop, lg]) == [1, 1])
        #expect(GridLayout.split(count: 1, weights: [laptop, lg]) == [0, 1])
        #expect(GridLayout.split(count: 6, weights: [lg, lg]) == [3, 3])
        #expect(GridLayout.split(count: 3, weights: [lg, lg, lg]) == [1, 1, 1])
    }

    @Test func equalScreensTieGoesToFirst() {
        #expect(GridLayout.split(count: 1, weights: [lg, lg]) == [1, 0])
        #expect(GridLayout.split(count: 3, weights: [lg, lg]) == [2, 1])
    }

    @Test func degenerateInput() {
        #expect(GridLayout.split(count: 4, weights: []) == [])
        #expect(GridLayout.split(count: 0, weights: [lg, laptop]) == [0, 0])
        #expect(GridLayout.split(count: 4, weights: [0, 0]) == [2, 2])
    }
}
