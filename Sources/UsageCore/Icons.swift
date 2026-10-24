import SwiftUI

struct ProviderGlyph: View {
    let kind: ProviderKind
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(kind.accent.opacity(0.10))
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(kind.accent.opacity(0.30), lineWidth: 0.8)
            glyph
                .foregroundStyle(kind.accent)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .opencodeGo:
            OpenCodeMark()
                .stroke(kind.accent, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.52, height: size * 0.46)
        case .openai:
            OpenAIKnot()
                .stroke(kind.accent, style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.56, height: size * 0.56)
        case .cursor:
            CursorMark()
                .fill(kind.accent)
                .frame(width: size * 0.44, height: size * 0.52)
        }
    }
}

/// `>` plus a trailing underscore.
struct OpenCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.04, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.04, y: h * 0.92))
        path.move(to: CGPoint(x: w * 0.52, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.96, y: h * 0.92))
        return path
    }
}

/// Two nested hexagons: a lightweight nod to the OpenAI knot.
struct OpenAIKnot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(Self.hexagon(in: rect, rotation: 0))
        path.addPath(Self.hexagon(in: rect, rotation: .pi / 6, inset: 0.16))
        return path
    }

    private static func hexagon(in rect: CGRect, rotation: CGFloat, inset: CGFloat = 0) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * (1 - inset)
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2 + rotation
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Classic cursor arrow.
struct CursorMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.06, y: h * 0.02))
        path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.94))
        path.addLine(to: CGPoint(x: w * 0.60, y: h * 1.0))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.06, y: h * 0.92))
        path.closeSubpath()
        return path
    }
}

/// Rounded neon meter with hairline ticks.
struct NeonBar: View {
    var fraction: Double
    var accent: Color
    var height: CGFloat = 22
    var showsTicks: Bool = true
    var monochrome: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fill = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(monochrome ? Color.white.opacity(0.14) : Color(hex: 0x1B1B1E))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: monochrome
                                ? [Color.white.opacity(0.95), Color.white.opacity(0.72)]
                                : [accent.opacity(0.98), accent.opacity(0.62)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule().fill(
                            LinearGradient(
                                colors: monochrome
                                    ? [.clear, .clear]
                                    : [Color.white.opacity(0.22), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    )
                    .frame(width: fill <= 0 ? 0 : max(9, width * fill))
                    .shadow(
                        color: monochrome || height < 5 ? .clear : accent.opacity(0.40),
                        radius: height < 10 ? 4 : 11
                    )
                    .shadow(
                        color: monochrome || height < 5 ? .clear : accent.opacity(0.25),
                        radius: height < 10 ? 2 : 4
                    )
                if showsTicks {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.28))
                                .frame(width: 1)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .frame(height: height)
    }
}

