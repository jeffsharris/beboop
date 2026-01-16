import SwiftUI

struct HighContrastMobileView: View {
    private struct MovingShape: Identifiable {
        enum Kind {
            case circle
            case roundedRect
            case capsule
            case blob
        }

        let id = UUID()
        let kind: Kind
        let start: CGPoint
        let size: CGSize
        let speed: CGFloat
        let rotation: Angle
    }

    @State private var startTime = Date()

    private let shapes: [MovingShape] = [
        MovingShape(kind: .circle, start: CGPoint(x: 0.05, y: 0.25), size: CGSize(width: 0.16, height: 0.16), speed: 0.018, rotation: .degrees(0)),
        MovingShape(kind: .roundedRect, start: CGPoint(x: 0.3, y: 0.45), size: CGSize(width: 0.22, height: 0.14), speed: 0.014, rotation: .degrees(12)),
        MovingShape(kind: .capsule, start: CGPoint(x: 0.55, y: 0.65), size: CGSize(width: 0.24, height: 0.12), speed: 0.016, rotation: .degrees(-8)),
        MovingShape(kind: .blob, start: CGPoint(x: 0.8, y: 0.35), size: CGSize(width: 0.2, height: 0.18), speed: 0.012, rotation: .degrees(6)),
        MovingShape(kind: .circle, start: CGPoint(x: 0.12, y: 0.75), size: CGSize(width: 0.14, height: 0.14), speed: 0.02, rotation: .degrees(0))
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geometry in
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSince(startTime)

                        for shape in shapes {
                            draw(shape: shape, in: size, at: time, context: &context)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func draw(shape: MovingShape, in size: CGSize, at time: TimeInterval, context: inout GraphicsContext) {
        let minDimension = min(size.width, size.height)
        let width = minDimension * shape.size.width
        let height = minDimension * shape.size.height
        let travelDistance = size.width + width * 2

        let rawX = shape.start.x * size.width + CGFloat(time) * shape.speed * size.width
        let wrappedX = (rawX + width).truncatingRemainder(dividingBy: travelDistance) - width
        let y = shape.start.y * size.height

        context.saveGState()
        context.translateBy(x: wrappedX, y: y)
        context.rotate(by: shape.rotation)

        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let path = path(for: shape.kind, in: rect)
        context.fill(path, with: .color(.black))

        context.restoreGState()
    }

    private func path(for kind: MovingShape.Kind, in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            return Path(ellipseIn: rect)
        case .roundedRect:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.25)
        case .capsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.5)
        case .blob:
            return blobPath(in: rect)
        }
    }

    private func blobPath(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.4),
            control1: CGPoint(x: x + w * 0.78, y: y + h * 0.02),
            control2: CGPoint(x: x + w, y: y + h * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.72, y: y + h),
            control1: CGPoint(x: x + w, y: y + h * 0.75),
            control2: CGPoint(x: x + w * 0.9, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.2, y: y + h * 0.88),
            control1: CGPoint(x: x + w * 0.48, y: y + h),
            control2: CGPoint(x: x + w * 0.3, y: y + h * 1.05)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.1, y: y + h * 0.35),
            control1: CGPoint(x: x + w * 0.1, y: y + h * 0.8),
            control2: CGPoint(x: x, y: y + h * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    HighContrastMobileView()
}
