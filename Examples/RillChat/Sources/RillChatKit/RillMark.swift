import SwiftUI

/// The Rill mark drawn in pure SwiftUI — flowing lines of streamed text with a
/// trailing token. Solid accent (no gradients), so it stays crisp on any tile.
public struct RillMark: View {
    public var color: Color
    public init(color: Color) { self.color = color }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let w = s * 0.086
            Path { p in
                func line(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat) {
                    p.move(to: CGPoint(x: s * x0, y: s * y))
                    p.addCurve(to: CGPoint(x: s * x1, y: s * y),
                               control1: CGPoint(x: s * (x0 + (x1 - x0) * 0.35), y: s * (y - 0.028)),
                               control2: CGPoint(x: s * (x0 + (x1 - x0) * 0.7), y: s * (y + 0.030)))
                }
                line(0.33, 0.18, 0.66)
                line(0.49, 0.18, 0.82)
                line(0.65, 0.18, 0.71)
            }
            .stroke(color, style: StrokeStyle(lineWidth: w, lineCap: .round))
            Circle().fill(color).frame(width: w * 1.15).position(x: s * 0.80, y: s * 0.80)
            Circle().fill(color.opacity(0.55)).frame(width: w * 0.9).position(x: s * 0.90, y: s * 0.79)
        }
    }
}

/// The mark on a subtle rounded tile — the assistant avatar.
public struct RillAvatar: View {
    let p: Palette
    public init(_ p: Palette) { self.p = p }
    public var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(p.surface)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(p.border, lineWidth: 1))
            .overlay(RillMark(color: p.accent).padding(6))
            .frame(width: 32, height: 32)
    }
}
