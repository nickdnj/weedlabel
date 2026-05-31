import SwiftUI

/// The Pocketbud brand mark: an unlit joint tucked into a green pocket-protector
/// flap on a shirt pocket. The pocket conceals its contents (no leaf shown) and
/// the joint is unlit (no ember, no smoke) — deliberately understated/ambiguous
/// for App Store review. Vector-drawn, transparent background, scales to `size`.
struct PocketbudMark: View {
    var size: CGFloat = 44

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 100.0
            let box = CGAffineTransform(scaleX: k, y: k)

            // Pocket body — conceals its contents.
            let pocketBody = Path(roundedRect: CGRect(x: 20, y: 54, width: 60, height: 40),
                                  cornerRadius: 9)
            ctx.fill(pocketBody.applying(box), with: .color(Brand.greenDeep))

            // Unlit joint, tilted, base hidden behind the flap. No ember, no smoke.
            let jointBox = box.translatedBy(x: 54, y: 50).rotated(by: 18 * .pi / 180)
            let joint = Path(roundedRect: CGRect(x: -3, y: -25, width: 6, height: 50), cornerRadius: 3)
            ctx.fill(joint.applying(jointBox), with: .color(Brand.cream))
            ctx.stroke(joint.applying(jointBox), with: .color(Brand.greenDeep.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.2 * k))

            // Pocket-protector flap with scalloped hem (the joint pokes out of it).
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
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
