//
//  DesignSystem.swift
//  PDFHandler
//
//  Design system: Terminal precision meets calligraphic craft
//  "Opening a terminal in a Kyoto tea house"
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    // MARK: Light Mode

    /// Warm white, like fine paper - #FAFAFA
    static let paperBackground = Color(hex: "FAFAFA")

    /// Pure white for cards/panels - #FFFFFF
    static let surface = Color.white

    /// Ink-like black, not pure - #1A1A1A
    static let inkBlack = Color(hex: "1A1A1A")

    /// Faded, recessive text - #6B6B6B
    static let stonegrey = Color(hex: "6B6B6B")

    /// Subtle borders - #E0E0E0
    static let mist = Color(hex: "E0E0E0")

    /// Slider track - #E5E5E5
    static let ashGrey = Color(hex: "E5E5E5")

    // MARK: Accents

    /// Terminal green - cursor, success - #00D47E
    static let terminalGreen = Color(hex: "00D47E")

    /// Muted terminal green for dark mode
    static let phosphorGreen = Color(hex: "00B86B")

    /// Deep emphasis - #0D0D0D
    static let sumiBlack = Color(hex: "0D0D0D")

    // MARK: Dark Mode

    /// Dark mode base - #1C1C1E
    static let charcoal = Color(hex: "1C1C1E")

    /// Dark mode surface - #2C2C2E
    static let sumiGrey = Color(hex: "2C2C2E")

    // MARK: Semantic Colors

    static let primaryText = Color("PrimaryText", bundle: nil)
    static let secondaryText = Color("SecondaryText", bundle: nil)
    static let accent = Color("Accent", bundle: nil)

    // MARK: Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Colors

struct SumiColors {
    @Environment(\.colorScheme) var colorScheme

    var background: Color {
        colorScheme == .dark ? .charcoal : .paperBackground
    }

    var surface: Color {
        colorScheme == .dark ? .sumiGrey : .surface
    }

    var primaryText: Color {
        colorScheme == .dark ? .white : .inkBlack
    }

    var secondaryText: Color {
        colorScheme == .dark ? Color(hex: "8E8E93") : .stonegrey
    }

    var accent: Color {
        colorScheme == .dark ? .phosphorGreen : .terminalGreen
    }

    var border: Color {
        colorScheme == .dark ? Color(hex: "3A3A3C") : .mist
    }
}

// MARK: - Typography

struct SumiTypography {
    // UI Labels - SF Pro Text (system default)
    static let label = Font.system(size: 13, weight: .regular, design: .default)
    static let labelMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let title = Font.system(size: 22, weight: .semibold, design: .default)

    // Code / Data - SF Mono
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoLarge = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let monoTitle = Font.system(size: 18, weight: .medium, design: .monospaced)

    // Command-style large text
    static let command = Font.system(size: 24, weight: .light, design: .monospaced)
    static let commandLarge = Font.system(size: 32, weight: .light, design: .monospaced)
}

// MARK: - View Modifiers

struct SumiCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
            .cornerRadius(8)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

struct SumiTextButtonStyle: ButtonStyle {
    let isAccent: Bool
    @Environment(\.colorScheme) var colorScheme

    init(accent: Bool = false) {
        self.isAccent = accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SumiTypography.mono)
            .foregroundStyle(
                isAccent
                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    : (colorScheme == .dark ? Color.white : Color.stonegrey)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .contentShape(Rectangle())
    }
}

extension View {
    func sumiCard() -> some View {
        modifier(SumiCardStyle())
    }
}

extension ButtonStyle where Self == SumiTextButtonStyle {
    static var sumiText: SumiTextButtonStyle { SumiTextButtonStyle() }
    static var sumiAccent: SumiTextButtonStyle { SumiTextButtonStyle(accent: true) }
}

// MARK: - Calligraphic Mark (Logo/Watermark)

struct EnsoMark: View {
    let opacity: Double
    let size: CGFloat

    init(opacity: Double = 0.3, size: CGFloat = 200) {
        self.opacity = opacity
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.8

            // Partial ensō - the beginning of a brush stroke
            var path = Path()

            // Start from top, sweep about 270 degrees with varying thickness
            let startAngle = Angle(degrees: -90)
            let endAngle = Angle(degrees: 180)

            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )

            // Draw with brush-like stroke
            context.stroke(
                path,
                with: .color(.inkBlack.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: size * 0.08,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            // Add slight taper at the end (brush lifting)
            let taperPath = Path { p in
                let taperStart = Angle(degrees: 150)
                let taperEnd = Angle(degrees: 180)
                p.addArc(
                    center: center,
                    radius: radius,
                    startAngle: taperStart,
                    endAngle: taperEnd,
                    clockwise: false
                )
            }

            context.stroke(
                taperPath,
                with: .color(.inkBlack.opacity(opacity * 0.6)),
                style: StrokeStyle(
                    lineWidth: size * 0.05,
                    lineCap: .round
                )
            )
        }
        .frame(width: size, height: size)
    }
}

struct BrushStrokeMark: View {
    let opacity: Double
    let size: CGFloat
    @State private var cursorVisible = true

    init(opacity: Double = 0.3, size: CGFloat = 100) {
        self.opacity = opacity
        self.size = size
    }

    var body: some View {
        HStack(spacing: size * 0.1) {
            // Vertical brush stroke
            Canvas { context, canvasSize in
                var path = Path()

                // Organic vertical stroke with slight curve
                path.move(to: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.1))

                path.addQuadCurve(
                    to: CGPoint(x: canvasSize.width * 0.48, y: canvasSize.height * 0.9),
                    control: CGPoint(x: canvasSize.width * 0.55, y: canvasSize.height * 0.5)
                )

                context.stroke(
                    path,
                    with: .color(.inkBlack.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: size * 0.12,
                        lineCap: .round
                    )
                )
            }
            .frame(width: size * 0.3, height: size)

            // Blinking cursor
            Rectangle()
                .fill(Color.terminalGreen.opacity(cursorVisible ? opacity : 0))
                .frame(width: size * 0.05, height: size * 0.6)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: cursorVisible)
                .onAppear { cursorVisible = false }
        }
    }
}

// MARK: - CLI Progress Bar

struct CLIProgressBar: View {
    let progress: Double
    let label: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Progress line
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.sumiGrey : Color.ashGrey)
                        .frame(height: 2)

                    // Fill
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        .frame(width: geometry.size.width * progress, height: 2)
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 2)

            // Status text
            Text(label)
                .font(SumiTypography.monoSmall)
                .foregroundStyle(colorScheme == .dark ? Color(hex: "8E8E93") : Color.stonegrey)
        }
    }
}

// MARK: - Minimal Slider

struct SumiSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Value display
            HStack {
                Text(label)
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "8E8E93") : Color.stonegrey)

                Spacer()

                Text("\(Int(value * 100))%")
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.inkBlack)
            }

            // Custom slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.sumiGrey : Color.ashGrey)
                        .frame(height: 2)

                    // Filled portion
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        .frame(width: geometry.size.width * normalizedValue, height: 2)

                    // Thumb - vertical bar (cursor/brushstroke motif)
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white : Color.inkBlack)
                        .frame(width: 2, height: 16)
                        .offset(x: geometry.size.width * normalizedValue - 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let newValue = gesture.location.x / geometry.size.width
                            value = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, newValue))
                        }
                )
            }
            .frame(height: 16)
        }
    }

    private var normalizedValue: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// MARK: - Ink Dissolve Animation

struct InkDissolveModifier: ViewModifier {
    let isActive: Bool
    @State private var particles: [InkParticle] = []

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isActive ? 0 : 1)

            if isActive {
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.terminalGreen.opacity(particle.opacity))
                        .frame(width: particle.size, height: particle.size)
                        .offset(x: particle.x, y: particle.y)
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                createParticles()
                animateParticles()
            }
        }
    }

    private func createParticles() {
        particles = (0..<8).map { _ in
            InkParticle(
                x: CGFloat.random(in: -20...20),
                y: CGFloat.random(in: -10...10),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.3...0.8)
            )
        }
    }

    private func animateParticles() {
        withAnimation(.easeOut(duration: 0.8)) {
            particles = particles.map { particle in
                var p = particle
                p.x += CGFloat.random(in: -30...30)
                p.y += CGFloat.random(in: -20...20)
                p.opacity = 0
                return p
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            particles = []
        }
    }
}

struct InkParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
}

extension View {
    func inkDissolve(isActive: Bool) -> some View {
        modifier(InkDissolveModifier(isActive: isActive))
    }
}

// MARK: - Cursor Blink Animation

struct CursorBlinkView: View {
    @State private var isVisible = true
    let color: Color

    init(color: Color = .terminalGreen) {
        self.color = color
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 2, height: 18)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}

// MARK: - Previews

#Preview("Colors") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ColorSwatch(color: .paperBackground, name: "Paper")
            ColorSwatch(color: .inkBlack, name: "Ink")
            ColorSwatch(color: .terminalGreen, name: "Terminal")
            ColorSwatch(color: .stonegrey, name: "Stone")
        }

        HStack(spacing: 20) {
            ColorSwatch(color: .charcoal, name: "Charcoal")
            ColorSwatch(color: .sumiGrey, name: "Sumi")
            ColorSwatch(color: .phosphorGreen, name: "Phosphor")
        }
    }
    .padding()
}

#Preview("Marks") {
    HStack(spacing: 40) {
        EnsoMark(opacity: 0.3, size: 100)
        BrushStrokeMark(opacity: 0.4, size: 80)
    }
    .padding()
}

#Preview("Progress") {
    VStack(spacing: 20) {
        CLIProgressBar(progress: 0.47, label: "compressing → 47% → 1.2 MB")
        CLIProgressBar(progress: 0.8, label: "converting → 80%")
    }
    .padding()
    .frame(width: 300)
}

#Preview("Slider") {
    SumiSlider(value: .constant(0.5), range: 0.1...1.0, label: "target size")
        .padding()
        .frame(width: 300)
}

private struct ColorSwatch: View {
    let color: Color
    let name: String

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
            Text(name)
                .font(.caption)
        }
    }
}
