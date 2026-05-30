import SwiftUI

/// The Pocketbud brand mark: a stylized cannabis leaf popping out of a green
/// pocket-protector flap. Vector-drawn (no asset), transparent background, so it
/// drops into headers and wordmarks the way the old `music.note` glyph did, and
/// scales to any `size`. Matches the app icon's hero element (`pocketbud-icon.svg`).
struct PocketbudMark: View {
    var size: CGFloat = 44

    /// One leaflet, in a 0…-470 "up" coordinate space (matches the icon SVG).
    private static let leaflet: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: -470),
                   control1: CGPoint(x: -64, y: -150), control2: CGPoint(x: -36, y: -340))
        p.addCurve(to: CGPoint(x: 0, y: 0),
                   control1: CGPoint(x: 36, y: -340), control2: CGPoint(x: 64, y: -150))
        p.closeSubpath()
        return p
    }()

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 100.0
            let box = CGAffineTransform(scaleX: k, y: k)

            // Pocket body (drawn first; contains the leaf + joint bases).
            let pocketBody = Path(roundedRect: CGRect(x: 20, y: 54, width: 60, height: 40),
                                  cornerRadius: 9)
            ctx.fill(pocketBody.applying(box), with: .color(Brand.greenDeep))

            // Leaf (5 leaflets + stem), emerges above the pocket.
            let leafBase = box.translatedBy(x: 50, y: 72).scaledBy(x: 0.123, y: 0.123)
            let leaflets: [(Double, CGFloat)] = [(0, 1), (-36, 0.82), (36, 0.82), (-70, 0.55), (70, 0.55)]
            var leaf = Path()
            for (rot, len) in leaflets {
                let t = leafBase.rotated(by: rot * .pi / 180).scaledBy(x: 1, y: len)
                leaf.addPath(Self.leaflet.applying(t))
            }
            let stem = Path(roundedRect: CGRect(x: -14, y: 0, width: 28, height: 120), cornerRadius: 14)
            leaf.addPath(stem.applying(leafBase))
            ctx.fill(leaf, with: .color(Brand.greenBright))

            // Lit joint, tilted up-right (base hidden behind the flap).
            let jointBox = box.translatedBy(x: 71, y: 50).rotated(by: 20 * .pi / 180)
            let joint = Path(roundedRect: CGRect(x: -2.5, y: -24, width: 5, height: 48), cornerRadius: 2.5)
            ctx.fill(joint.applying(jointBox), with: .color(Brand.cream))
            ctx.stroke(joint.applying(jointBox), with: .color(Brand.greenDeep.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1.1 * k))

            // Pocket-protector flap with scalloped hem (the leaf + joint pop out of it).
            var flap = Path()
            flap.move(to: CGPoint(x: 16, y: 52))
            flap.addLine(to: CGPoint(x: 84, y: 52))
            flap.addLine(to: CGPoint(x: 84, y: 64))
            var x: CGFloat = 84
            var dir: CGFloat = 1
            let scallop: CGFloat = 17
            for _ in 0..<4 {
                flap.addQuadCurve(to: CGPoint(x: x - scallop, y: 64),
                                  control: CGPoint(x: x - scallop / 2, y: 64 + 5 * dir))
                x -= scallop
                dir = -dir
            }
            flap.closeSubpath()
            ctx.fill(flap.applying(box), with: .color(Brand.green))

            // Ember + smoke trail curling to the right (drawn on top).
            ctx.fill(Path(ellipseIn: CGRect(x: 76 * k, y: 24.6 * k, width: 6 * k, height: 4.8 * k)),
                     with: .color(Brand.ember))
            var smoke = Path()
            smoke.move(to: CGPoint(x: 79, y: 24))
            smoke.addCurve(to: CGPoint(x: 87, y: 15),
                           control1: CGPoint(x: 80, y: 20), control2: CGPoint(x: 89, y: 21))
            smoke.addCurve(to: CGPoint(x: 85, y: 4),
                           control1: CGPoint(x: 85, y: 10), control2: CGPoint(x: 91, y: 9))
            ctx.stroke(smoke.applying(box), with: .color(Brand.cream.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2.3 * k, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
