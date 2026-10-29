import CoreGraphics

/// Where each widget stack sits. Every stack is square; the layouts differ in
/// how the squares are sized and arranged. Stack 1 is the featured one in Hero
/// and Spotlight.
enum WidgetGrid {
    static func frames(count: Int, layout: WidgetLayout, in size: CGSize) -> [CGRect] {
        let n = min(max(count, 1), StandbyConfig.maxStacks)
        if n == 1 { return grid(1, size) }
        switch layout {
        case .grid: return grid(n, size)
        case .hero: return hero(n, size)
        case .spotlight: return n >= 3 ? spotlight(n, size) : hero(n, size)
        case .strip: return strip(n, size, wave: false)
        case .wave: return n >= 3 ? strip(n, size, wave: true) : grid(n, size)
        }
    }

    /// One row for up to three stacks, two rows (the second centered) beyond.
    private static func grid(_ n: Int, _ size: CGSize) -> [CGRect] {
        let rows = n > 3 ? 2 : 1
        let cols = (n + rows - 1) / rows
        let gap = size.width * (cols >= 3 || rows == 2 ? 0.03 : 0.04)
        let side: CGFloat
        if n == 1 {
            side = size.height * 0.8
        } else {
            side = min((size.width - gap * CGFloat(cols + 1)) / CGFloat(cols),
                       (size.height * (rows == 1 ? 0.84 : 0.9) - gap * CGFloat(rows - 1)) / CGFloat(rows))
        }
        let top = (size.height - side * CGFloat(rows) - gap * CGFloat(rows - 1)) / 2
        var frames: [CGRect] = []
        for row in 0..<rows {
            let items = row == 0 ? cols : n - cols
            let left = (size.width - side * CGFloat(items) - gap * CGFloat(items - 1)) / 2
            for c in 0..<items {
                frames.append(square(left + CGFloat(c) * (side + gap), top + CGFloat(row) * (side + gap), side))
            }
        }
        return frames
    }

    /// A large stack on the left, the others in a block of smaller ones to its right.
    private static func hero(_ n: Int, _ size: CGSize) -> [CGRect] {
        let small = n - 1
        let cols = small <= 2 ? 1 : 2
        let rows = max((small + cols - 1) / cols, 2)
        let gap = size.width * 0.03
        let maxWidth = size.width * 0.92
        // big + gap + cols * smallSide + gaps between them must fit the width,
        // where smallSide = (big - gaps between rows) / rows.
        let k = CGFloat(cols) / CGFloat(rows)
        let fit = (maxWidth - gap * CGFloat(cols) + k * gap * CGFloat(rows - 1)) / (1 + k)
        let big = min(fit, size.height * 0.84)
        let side = (big - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let total = big + gap + CGFloat(cols) * side + CGFloat(cols - 1) * gap
        let x0 = (size.width - total) / 2
        let y0 = (size.height - big) / 2

        var frames = [square(x0, y0, big)]
        let usedRows = (small + cols - 1) / cols
        let blockTop = y0 + (big - (CGFloat(usedRows) * side + CGFloat(usedRows - 1) * gap)) / 2
        for i in 0..<small {
            let row = i / cols
            let inRow = min(cols, small - row * cols)
            let rowLeft = x0 + big + gap + (CGFloat(cols - inRow) * (side + gap)) / 2
            frames.append(square(rowLeft + CGFloat(i % cols) * (side + gap), blockTop + CGFloat(row) * (side + gap), side))
        }
        return frames
    }

    /// A large stack in the middle with columns of smaller ones on each side.
    private static func spotlight(_ n: Int, _ size: CGSize) -> [CGRect] {
        let small = n - 1
        let leftCount = small / 2
        let rightCount = small - leftCount
        let rows = max(rightCount, 2)
        let gap = size.width * 0.03
        let maxWidth = size.width * 0.94
        let fit = (maxWidth - 2 * gap + 2 * gap * CGFloat(rows - 1) / CGFloat(rows)) / (1 + 2 / CGFloat(rows))
        let big = min(fit, size.height * 0.84)
        let side = (big - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let x0 = (size.width - (big + 2 * side + 2 * gap)) / 2
        let y0 = (size.height - big) / 2

        func column(_ count: Int, x: CGFloat) -> [CGRect] {
            let top = y0 + (big - (CGFloat(count) * side + CGFloat(count - 1) * gap)) / 2
            return (0..<count).map { square(x, top + CGFloat($0) * (side + gap), side) }
        }
        return [square(x0 + side + gap, y0, big)]
            + column(leftCount, x: x0)
            + column(rightCount, x: x0 + side + gap + big + gap)
    }

    /// Everything in one row; with `wave`, alternate stacks ride high and low.
    private static func strip(_ n: Int, _ size: CGSize, wave: Bool) -> [CGRect] {
        let gap = size.width * (wave ? 0.022 : 0.025)
        let side = min((size.width * 0.94 - gap * CGFloat(n - 1)) / CGFloat(n), size.height * (wave ? 0.5 : 0.6))
        let left = (size.width - side * CGFloat(n) - gap * CGFloat(n - 1)) / 2
        return (0..<n).map { i in
            let lift = wave ? (i % 2 == 0 ? -1 : 1) * side * 0.24 : 0
            return square(left + CGFloat(i) * (side + gap), (size.height - side) / 2 + lift, side)
        }
    }

    private static func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: side, height: side)
    }
}
