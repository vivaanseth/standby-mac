import SwiftUI

struct DialStyle {
    var face: Color? = Palette.dialFace
    var numerals: Color? = .white
    var numeralSize: CGFloat = 0.22
    var numeralRadius: CGFloat = 0.75
    var numeralWeight: Font.Weight = .semibold
    var numeralDesign: Font.Design = .rounded
    var majorNumeralsOnly = false
    var minuteTicks: Color? = Color.white.opacity(0.28)
    var hourTicks: Color? = nil
    var tickInset: CGFloat = 0.94
    var hands: Color = .white
    var handWidth: CGFloat = 1
    var second: Color? = Palette.orange
    var label: String?
    var labelColor: Color = Palette.secondary

    static let widget = DialStyle()

    /// The Analog clock face's dial: open, with tinted numerals and fine ticks.
    /// `face` puts a backing behind it where it sits on a picture.
    static func analogFace(_ tint: Tint, face: Color? = nil) -> DialStyle {
        DialStyle(face: face,
                  numerals: tint.light,
                  numeralSize: 0.19,
                  numeralRadius: 0.75,
                  numeralWeight: .medium,
                  minuteTicks: Color.white.opacity(0.32),
                  hourTicks: .white,
                  tickInset: 0.98,
                  hands: .white,
                  handWidth: 0.85,
                  second: tint.base)
    }

    static func worldClock(isDay: Bool) -> DialStyle {
        DialStyle(face: isDay ? .white : Palette.dialFace,
                  numerals: isDay ? .black : .white,
                  numeralSize: 0.21,
                  numeralRadius: 0.76,
                  minuteTicks: nil,
                  hands: isDay ? .black : .white,
                  handWidth: 1.15,
                  second: Palette.orange)
    }
}

/// A clock dial drawn entirely in a Canvas so it stays sharp at any size.
struct AnalogDial: View {
    var date: Date
    var timeZone: TimeZone = .current
    var style: DialStyle = .widget

    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(c.second ?? 0)
        let minutes = Double(c.minute ?? 0) + seconds / 60
        let hours = Double((c.hour ?? 0) % 12) + minutes / 60
        let style = style

        return Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
                CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
            }

            if let face = style.face {
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(face))
            }

            if let tick = style.minuteTicks {
                var p = Path()
                for i in 0..<60 where !(style.hourTicks != nil && i % 5 == 0) {
                    let a = Double(i) / 60 * 2 * .pi
                    p.move(to: point(r * style.tickInset, a))
                    p.addLine(to: point(r * (style.tickInset - 0.05), a))
                }
                ctx.stroke(p, with: .color(tick), style: StrokeStyle(lineWidth: r * 0.014, lineCap: .round))
            }
            if let tick = style.hourTicks {
                var p = Path()
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi
                    p.move(to: point(r * style.tickInset, a))
                    p.addLine(to: point(r * (style.tickInset - 0.1), a))
                }
                ctx.stroke(p, with: .color(tick), style: StrokeStyle(lineWidth: r * 0.03, lineCap: .round))
            }

            if let numeralColor = style.numerals {
                let font = Font.system(size: r * style.numeralSize, weight: style.numeralWeight, design: style.numeralDesign)
                for h in 1...12 where !style.majorNumeralsOnly || h % 3 == 0 {
                    let a = Double(h) / 12 * 2 * .pi
                    ctx.draw(Text("\(h)").font(font).foregroundStyle(numeralColor), at: point(r * style.numeralRadius, a))
                }
            }

            if let label = style.label {
                ctx.draw(Text(label).font(.system(size: r * 0.15, weight: .semibold)).foregroundStyle(style.labelColor),
                         at: CGPoint(x: center.x, y: center.y - r * 0.36))
            }

            let w = style.handWidth
            func hand(_ angle: Double, length: CGFloat, width: CGFloat) {
                var stem = Path()
                stem.move(to: center)
                stem.addLine(to: point(r * 0.14, angle))
                ctx.stroke(stem, with: .color(style.hands), style: StrokeStyle(lineWidth: r * 0.035 * w, lineCap: .round))
                var body = Path()
                body.move(to: point(r * 0.14, angle))
                body.addLine(to: point(length, angle))
                ctx.stroke(body, with: .color(style.hands), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand(hours / 12 * 2 * .pi, length: r * 0.5, width: r * 0.085 * w)
            hand(minutes / 60 * 2 * .pi, length: r * 0.8, width: r * 0.075 * w)
            let capR = r * 0.06 * w
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - capR, y: center.y - capR, width: capR * 2, height: capR * 2)), with: .color(style.hands))

            if let sc = style.second {
                let a = seconds / 60 * 2 * .pi
                var p = Path()
                p.move(to: point(-r * 0.18, a))
                p.addLine(to: point(r * 0.88, a))
                ctx.stroke(p, with: .color(sc), style: StrokeStyle(lineWidth: r * 0.02, lineCap: .round))
                let sR = r * 0.045
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - sR, y: center.y - sR, width: sR * 2, height: sR * 2)), with: .color(sc))
                let dot = r * 0.018
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(style.face ?? .black))
            }
        }
    }
}
