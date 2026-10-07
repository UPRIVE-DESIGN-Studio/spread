import CoreGraphics
import Foundation

/// Pure grid math: n windows → n frames that evenly fill a rect.
///
/// The column count is chosen per screen shape: every candidate `cols` in 1...n is scored by how far
/// its worst cell strays from `targetCellAspect` (log ratio, so too wide and too tall count equally).
/// A short last row widens its cells to fill the row, so the grid has no holes.
nonisolated enum GridLayout {
    static let defaultTargetCellAspect: CGFloat = 1.2

    /// Frames in reading order (row by row, left to right), rounded to whole points.
    static func frames(
        count n: Int,
        in bounds: CGRect,
        gap: CGFloat,
        targetCellAspect: CGFloat = defaultTargetCellAspect
    ) -> [CGRect] {
        let rows = rowCounts(count: n, in: bounds, gap: gap, targetCellAspect: targetCellAspect)
        guard !rows.isEmpty else { return [] }

        let rowHeight = (bounds.height - gap * CGFloat(rows.count + 1)) / CGFloat(rows.count)
        var frames: [CGRect] = []
        frames.reserveCapacity(n)

        for (rowIndex, cellsInRow) in rows.enumerated() {
            let top = bounds.minY + gap + CGFloat(rowIndex) * (rowHeight + gap)
            let y0 = top.rounded()
            let y1 = (top + rowHeight).rounded()
            let cellWidth = (bounds.width - gap * CGFloat(cellsInRow + 1)) / CGFloat(cellsInRow)

            for column in 0..<cellsInRow {
                let left = bounds.minX + gap + CGFloat(column) * (cellWidth + gap)
                let x0 = left.rounded()
                let x1 = (left + cellWidth).rounded()
                frames.append(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
            }
        }
        return frames
    }

    /// Number of cells in each row, top to bottom. Every row is full except possibly the last.
    static func rowCounts(
        count n: Int,
        in bounds: CGRect,
        gap: CGFloat,
        targetCellAspect: CGFloat = defaultTargetCellAspect
    ) -> [Int] {
        guard n > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let target = max(targetCellAspect, 0.01)

        var best: (cols: Int, rows: Int, score: CGFloat)?
        for cols in 1...n {
            let rows = (n + cols - 1) / cols
            let lastRow = n - cols * (rows - 1)
            let height = (bounds.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
            let fullWidth = (bounds.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
            let lastWidth = (bounds.width - gap * CGFloat(lastRow + 1)) / CGFloat(lastRow)
            guard height > 0, fullWidth > 0, lastWidth > 0 else { continue }

            let score = max(
                abs(log(fullWidth / height / target)),
                abs(log(lastWidth / height / target))
            )
            let epsilon: CGFloat = 1e-9
            if let current = best {
                if score < current.score - epsilon
                    || (abs(score - current.score) <= epsilon && rows < current.rows) {
                    best = (cols, rows, score)
                }
            } else {
                best = (cols, rows, score)
            }
        }

        // Gaps too large for any grid: fall back to a single column so callers still get n frames.
        let cols = best?.cols ?? 1
        let rows = (n + cols - 1) / cols
        return (0..<rows).map { $0 < rows - 1 ? cols : n - cols * (rows - 1) }
    }

    /// Splits n windows across screens in proportion to their weights (usable area), using the
    /// largest-remainder method so the counts always add up to n. Ties go to the larger screen.
    static func split(count n: Int, weights: [CGFloat]) -> [Int] {
        guard n > 0, !weights.isEmpty else { return weights.map { _ in 0 } }
        let clamped = weights.map { max($0, 0) }
        let total = clamped.reduce(0, +)
        let shares = clamped.map { total > 0 ? CGFloat(n) * $0 / total : CGFloat(n) / CGFloat(weights.count) }
        var counts = shares.map { Int($0.rounded(.down)) }
        let byRemainder = shares.indices.sorted {
            let a = (shares[$0] - shares[$0].rounded(.down), clamped[$0], -$0)
            let b = (shares[$1] - shares[$1].rounded(.down), clamped[$1], -$1)
            return a > b
        }
        for index in byRemainder.prefix(n - counts.reduce(0, +)) {
            counts[index] += 1
        }
        return counts
    }
}
