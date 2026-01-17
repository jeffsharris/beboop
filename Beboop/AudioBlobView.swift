import SwiftUI

/// An organic blob shape that visualizes audio waveform data.
/// The blob's shape is determined by amplitude samples, and it rotates during playback
/// to indicate the current playback position.
struct AudioBlobView: View {
    /// Normalized waveform samples (0.0-1.0) that define the blob shape
    let samples: [Float]
    /// Current playback progress (0.0-1.0), nil when not playing
    let playbackProgress: Double?
    /// The tile's accent color
    let color: Color
    /// Size of the blob
    let size: CGFloat

    /// Base radius as proportion of size
    private let baseRadiusFactor: CGFloat = 0.32
    /// How much the amplitude affects radius (as proportion of base)
    private let amplitudeInfluence: CGFloat = 0.4
    /// Smoothing factor for the shape (higher = smoother)
    private let smoothingFactor: CGFloat = 0.4

    /// Current rotation in degrees (0-360)
    private var rotationDegrees: Double {
        (rotationTurns + effectiveProgress) * 360
    }

    /// Whether playback is active
    private var isPlaying: Bool {
        playbackProgress != nil
    }

    @State private var lastProgress: Double = 0
    @State private var rotationTurns: Double = 0

    private var effectiveProgress: Double {
        playbackProgress ?? lastProgress
    }

    var body: some View {
        ZStack {
            // Main blob shape
            BlobShape(
                samples: samples,
                baseRadiusFactor: baseRadiusFactor,
                amplitudeInfluence: amplitudeInfluence,
                smoothingFactor: smoothingFactor
            )
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.75)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * baseRadiusFactor
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotationDegrees))

            // Subtle inner glow
            BlobShape(
                samples: samples,
                baseRadiusFactor: baseRadiusFactor * 0.6,
                amplitudeInfluence: amplitudeInfluence * 0.5,
                smoothingFactor: smoothingFactor
            )
            .fill(Color.white.opacity(0.3))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotationDegrees))
        }
        .animation(isPlaying ? .linear(duration: 1.0 / 30.0) : .none, value: rotationDegrees)
        .onChange(of: playbackProgress) { _, newValue in
            guard let newValue else { return }
            if newValue + 0.5 < lastProgress {
                rotationTurns += 1
            }
            lastProgress = newValue
        }
    }
}

/// A custom shape that creates an organic blob from waveform samples
struct BlobShape: Shape {
    let samples: [Float]
    let baseRadiusFactor: CGFloat
    let amplitudeInfluence: CGFloat
    let smoothingFactor: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) * baseRadiusFactor

        // Need at least 3 points for a blob
        guard samples.count >= 3 else {
            return Path(ellipseIn: rect.insetBy(dx: rect.width * (0.5 - baseRadiusFactor),
                                                 dy: rect.height * (0.5 - baseRadiusFactor)))
        }

        // Generate control points around the circle
        let points = samples.enumerated().map { index, amplitude -> CGPoint in
            let angle = (CGFloat(index) / CGFloat(samples.count)) * 2 * .pi - .pi / 2
            let radiusVariation = CGFloat(amplitude) * baseRadius * amplitudeInfluence
            let radius = baseRadius + radiusVariation
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        return smoothedPath(through: points, smoothing: smoothingFactor, closed: true)
    }

    /// Creates a smooth closed path through the given points using Catmull-Rom to Bezier conversion
    private func smoothedPath(through points: [CGPoint], smoothing: CGFloat, closed: Bool) -> Path {
        guard points.count >= 3 else {
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                if closed { path.closeSubpath() }
            }
            return path
        }

        var path = Path()

        // For closed shapes, we need to wrap around
        let extendedPoints: [CGPoint]
        if closed {
            extendedPoints = [points[points.count - 1]] + points + [points[0], points[1]]
        } else {
            extendedPoints = points
        }

        path.move(to: points[0])

        for i in 0..<points.count {
            let p0 = extendedPoints[i]
            let p1 = extendedPoints[i + 1]
            let p2 = extendedPoints[i + 2]
            let p3 = i + 3 < extendedPoints.count ? extendedPoints[i + 3] : extendedPoints[i + 2]

            // Catmull-Rom to Bezier control points
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * smoothing / 3,
                y: p1.y + (p2.y - p0.y) * smoothing / 3
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * smoothing / 3,
                y: p2.y - (p3.y - p1.y) * smoothing / 3
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        if closed {
            path.closeSubpath()
        }

        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Sample with varied amplitudes
        AudioBlobView(
            samples: [0.3, 0.7, 0.4, 0.9, 0.5, 0.8, 0.3, 0.6, 0.4, 0.7, 0.5, 0.8],
            playbackProgress: nil,
            color: .green,
            size: 120
        )
        .background(Color.green)

        // Sample during playback (50% progress)
        AudioBlobView(
            samples: [0.2, 0.5, 0.8, 0.6, 0.3, 0.7, 0.4, 0.9, 0.5, 0.6, 0.3, 0.7],
            playbackProgress: 0.5,
            color: .blue,
            size: 120
        )
        .background(Color.blue)

        // Quieter recording
        AudioBlobView(
            samples: [0.2, 0.3, 0.25, 0.35, 0.2, 0.3, 0.25, 0.35, 0.2, 0.3, 0.25, 0.35],
            playbackProgress: nil,
            color: .purple,
            size: 120
        )
        .background(Color.purple)
    }
    .padding()
}
