import SwiftUI
import CoreText

public enum VerityTheme {
    public static let board = Color(red: 0.051, green: 0.059, blue: 0.071)
    public static let boardRaised = Color(red: 0.078, green: 0.090, blue: 0.114)
    public static let boardEdge = Color(red: 0.149, green: 0.169, blue: 0.204)
    public static let paper = Color(red: 0.925, green: 0.894, blue: 0.816)
    public static let paperHighlight = Color(red: 0.965, green: 0.941, blue: 0.878)
    public static let ink = Color(red: 0.129, green: 0.122, blue: 0.098)
    public static let etch = Color(red: 0.541, green: 0.576, blue: 0.639)
    public static let success = Color(red: 0.263, green: 0.722, blue: 0.435)
    public static let warning = Color(red: 0.949, green: 0.651, blue: 0.192)
    public static let danger = Color(red: 0.886, green: 0.310, blue: 0.286)

    public static func mono(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "IBM Plex Mono SemiBold" : "IBM Plex Mono", fixedSize: size)
    }

    public static func stencil(_ size: CGFloat) -> Font {
        .custom("Saira Stencil One", fixedSize: size)
    }
}

@MainActor
public enum VerityFonts {
    private static var registered = false

    public static func register() {
        guard !registered else { return }
        registered = true
        for name in ["IBMPlexMono-Regular", "IBMPlexMono-SemiBold", "SairaStencilOne-Regular"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

public enum StripCode {
    public static func make(_ reference: String) -> String {
        if reference == "Homework" || reference == "HW" { return "HW" }
        if reference.hasPrefix("Boards-") {
            let value = String(reference.dropFirst(7))
            if let separator = value.firstIndex(of: "-") {
                return "B·" + value[value.index(after: separator)...].prefix(3).uppercased()
            }
            let known = [
                "Mathematics": "B·MAT", "Science": "B·SCI", "English": "B·ENG",
                "IT": "B·IT", "Social Science": "B·SST", "Hindi/Sanskrit": "B·HIN",
            ]
            return known[value] ?? "B·" + value.prefix(3).uppercased()
        }
        let known = ["ZCO/ZIO": "ZCO", "IRIS Research": "IRIS", "Project Evidence": "PROJ", "CS50AI": "CS50"]
        return known[reference] ?? reference.prefix(5).uppercased()
    }
}

public struct VerityHardwareButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VerityTheme.mono(11, semibold: true))
            .tracking(0.45)
            .foregroundStyle(configuration.isPressed ? Color.white : Color(red: 0.725, green: 0.761, blue: 0.820))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color(red: 0.071, green: 0.082, blue: 0.106), Color(red: 0.094, green: 0.110, blue: 0.137)]
                        : [Color(red: 0.094, green: 0.110, blue: 0.137), Color(red: 0.071, green: 0.082, blue: 0.106)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 2)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(red: 0.227, green: 0.259, blue: 0.318), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(VerityTheme.boardEdge).frame(height: configuration.isPressed ? 1 : 2)
            }
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

public struct PaperStrip<Content: View>: View {
    private let accent: Color
    private let capText: String
    private let capSub: String?
    private let isSelected: Bool
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    public init(
        accent: Color = .accentColor,
        capText: String = "VER",
        capSub: String? = nil,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.capText = capText
        self.capSub = capSub
        self.isSelected = isSelected
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                accent
                LinearGradient(colors: [.white.opacity(0.2), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(capText)
                        .font(VerityTheme.mono(11, semibold: true))
                        .tracking(0.65)
                        .lineLimit(1)
                    if let capSub, !capSub.isEmpty {
                        Text(capSub)
                            .font(VerityTheme.mono(9))
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color(red: 0.063, green: 0.071, blue: 0.055))
                .padding(.horizontal, 8)
            }
            .frame(width: 68)
            content
                .foregroundStyle(VerityTheme.ink)
                .font(VerityTheme.mono(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 46)
        .background(
            LinearGradient(
                colors: [VerityTheme.paperHighlight, VerityTheme.paper, VerityTheme.paper.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            Canvas { context, size in
                var rules = Path()
                stride(from: 9.0, through: size.height, by: 9).forEach { y in
                    rules.move(to: CGPoint(x: 68, y: y))
                    rules.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(rules, with: .color(VerityTheme.ink.opacity(0.055)), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.95) : VerityTheme.boardEdge.opacity(contrast == .increased ? 0.8 : 0.42), lineWidth: isSelected ? 2 : 1)
        }
        .offset(x: isSelected ? 10 : (isHovering ? 3 : 0))
        .shadow(color: .black.opacity(isHovering || isSelected ? 0.5 : 0.35), radius: isHovering || isSelected ? 12 : 8, y: isSelected ? 7 : 4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isHovering)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

public struct BoardBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.078, green: 0.094, blue: 0.122), VerityTheme.board], center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: 700)
            Canvas { context, size in
                var path = Path()
                stride(from: 0.0, through: size.height, by: 3).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.white.opacity(0.012)), lineWidth: 1)
            }
            .accessibilityHidden(true)
        }
    }
}

public struct StatusLED: View {
    private let color: Color
    private let isActive: Bool

    public init(color: Color, isActive: Bool = true) {
        self.color = color
        self.isActive = isActive
    }

    public var body: some View {
        Circle()
            .fill(isActive ? color : VerityTheme.boardEdge)
            .frame(width: 7, height: 7)
            .shadow(color: isActive ? color.opacity(0.8) : .clear, radius: 4)
            .accessibilityHidden(true)
    }
}

public struct EmptyBay: View {
    private let title: String
    private let symbol: String
    private let detail: String

    public init(_ title: String, systemImage: String, detail: String) {
        self.title = title
        self.symbol = systemImage
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.8)
            Text(detail)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(VerityTheme.etch.opacity(0.68))
        }
        .foregroundStyle(VerityTheme.etch)
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(VerityTheme.boardEdge, style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
        }
        .accessibilityElement(children: .combine)
    }
}
