import SwiftUI

/// Pages stacked vertically; only the visible page and its neighbors are built.
struct VerticalPager<Content: View>: View {
    var count: Int
    var index: Int
    var offset: CGFloat
    var neighbors = true
    @ViewBuilder var content: (Int) -> Content

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                ForEach(0..<max(count, 1), id: \.self) { i in
                    if i == index || (neighbors && abs(i - index) == 1) {
                        content(i)
                            .frame(width: geo.size.width, height: h)
                            .clipped()
                            .offset(y: CGFloat(i - index) * h + offset)
                    }
                }
            }
            .frame(width: geo.size.width, height: h, alignment: .top)
        }
        .clipped()
    }
}

/// The vertical dots StandBy shows beside a stack while you swipe it.
struct StackIndicator: View {
    var count: Int
    var index: Int
    var dot: CGFloat

    var body: some View {
        VStack(spacing: dot * 0.9) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == index ? 0.95 : 0.3))
                    .frame(width: dot, height: dot)
            }
        }
    }
}
