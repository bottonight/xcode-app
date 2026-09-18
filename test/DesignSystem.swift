import SwiftUI

enum FabricTheme {
    static let indigo = Color(red: 0.18, green: 0.27, blue: 0.72)
    static let cyan = Color(red: 0.08, green: 0.65, blue: 0.72)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.94, green: 0.96, blue: 1),
            Color(uiColor: .systemGroupedBackground)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct BrandCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(FabricTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

extension View {
    func brandCard() -> some View {
        modifier(BrandCardModifier())
    }
}

struct ProjectSwitcherButton: View {
    let project: AppProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                Text(L10n.t(project.titleKey))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .tint(FabricTheme.indigo)
    }
}

struct SignalIndicator: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1 ... 3, id: \.self) { item in
                Capsule()
                    .fill(item <= level ? FabricTheme.cyan : Color.secondary.opacity(0.2))
                    .frame(width: 3, height: CGFloat(5 + item * 3))
            }
        }
        .accessibilityLabel(L10n.t("a11y.signal", level))
    }
}

struct BusyOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            HStack {
                ProgressView()
                Text(title)
                    .fontWeight(.medium)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
