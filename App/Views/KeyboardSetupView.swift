import SwiftUI

enum KeyboardTutorialPreference {
    private static let key = "keyboardTutorialSeen"

    static var hasSeen: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct KeyboardSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    private let totalSteps = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                pager
                pageDots
                actions
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Set up the keyboard")
                        .font(.system(size: 16, weight: .semibold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        KeyboardTutorialPreference.markSeen()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            KeyboardTutorialPreference.markSeen()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Four taps in iOS Settings")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Swipe through each step, then tap Open Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var pager: some View {
        TabView(selection: $currentStep) {
            TutorialStep(
                number: 1,
                instruction: "Tap General",
                screen: TutorialScreens.settingsHome
            ).tag(0)
            TutorialStep(
                number: 2,
                instruction: "Tap Keyboard",
                screen: TutorialScreens.general
            ).tag(1)
            TutorialStep(
                number: 3,
                instruction: "Tap Keyboards, then Add New Keyboard",
                screen: TutorialScreens.keyboard
            ).tag(2)
            TutorialStep(
                number: 4,
                instruction: "Select Much Better Authenticator",
                screen: TutorialScreens.addNewKeyboard
            ).tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(currentStep == i ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .padding(.vertical, 12)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "arrow.up.right.square")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Text("Privacy: the keyboard runs offline. Codes never leave your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

private struct TutorialStep: View {
    let number: Int
    let instruction: String
    let screen: MockScreen

    var body: some View {
        VStack(spacing: 16) {
            PhoneFrame(screen: screen)
                .frame(maxHeight: .infinity)
            VStack(spacing: 4) {
                Text("Step \(number) of 4")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text(instruction)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Phone Mockup

private struct PhoneFrame: View {
    let screen: MockScreen

    var body: some View {
        VStack(spacing: 0) {
            phoneNotch
            statusBar
            navBar
            Divider().opacity(0.3)
            rows
            Spacer(minLength: 0)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        .aspectRatio(220.0 / 440.0, contentMode: .fit)
        .frame(maxWidth: 240)
    }

    private var phoneNotch: some View {
        ZStack {
            Color.clear.frame(height: 14)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black)
                .frame(width: 70, height: 12)
                .padding(.top, 2)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "cellularbars").font(.system(size: 9))
                Image(systemName: "wifi").font(.system(size: 9))
                Image(systemName: "battery.100").font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .foregroundStyle(.primary)
    }

    private var navBar: some View {
        HStack {
            if let back = screen.backTitle {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(back)
                        .font(.system(size: 13))
                }
                .foregroundStyle(.blue)
            } else {
                Spacer().frame(width: 50)
            }
            Spacer()
            Text(screen.title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Spacer().frame(width: 50)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(screen.rows.enumerated()), id: \.offset) { idx, row in
                MockSettingsRow(row: row)
                if idx < screen.rows.count - 1 {
                    Divider()
                        .padding(.leading, 46)
                        .opacity(0.4)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct MockSettingsRow: View {
    let row: MockRow

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(row.iconBackground)
                        .frame(width: 24, height: 24)
                    Image(systemName: row.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(row.title)
                    .font(.system(size: 13, weight: row.emphasized ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: row.trailingIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if row.tapIndicator {
                TapIndicator()
                    .offset(x: -28)
            }
        }
    }
}

private struct TapIndicator: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(pulsing ? 1.08 : 1.0)
            .opacity(pulsing ? 0.85 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Mock data

private struct MockScreen {
    let title: String
    let backTitle: String?
    let rows: [MockRow]
}

private struct MockRow {
    let icon: String
    let iconBackground: Color
    let title: String
    var detail: String? = nil
    var trailingIcon: String = "chevron.right"
    var tapIndicator: Bool = false
    var emphasized: Bool = false
}

private enum TutorialScreens {
    static let settingsHome = MockScreen(
        title: "Settings",
        backTitle: nil,
        rows: [
            MockRow(icon: "airplane", iconBackground: .orange, title: "Airplane Mode"),
            MockRow(icon: "wifi", iconBackground: .blue, title: "Wi-Fi", detail: "Home"),
            MockRow(icon: "antenna.radiowaves.left.and.right", iconBackground: .green, title: "Cellular"),
            MockRow(icon: "gearshape.fill", iconBackground: .gray, title: "General", tapIndicator: true, emphasized: true),
            MockRow(icon: "person.fill", iconBackground: .blue, title: "Privacy & Security"),
            MockRow(icon: "display", iconBackground: .blue, title: "Display & Brightness"),
        ]
    )

    static let general = MockScreen(
        title: "General",
        backTitle: "Settings",
        rows: [
            MockRow(icon: "info.circle.fill", iconBackground: .gray, title: "About"),
            MockRow(icon: "arrow.triangle.2.circlepath", iconBackground: .blue, title: "Software Update"),
            MockRow(icon: "airplayvideo", iconBackground: .blue, title: "AirPlay & Handoff"),
            MockRow(icon: "iphone", iconBackground: .gray, title: "iPhone Storage"),
            MockRow(icon: "keyboard", iconBackground: .gray, title: "Keyboard", tapIndicator: true, emphasized: true),
            MockRow(icon: "globe", iconBackground: .gray, title: "Language & Region"),
        ]
    )

    static let keyboard = MockScreen(
        title: "Keyboard",
        backTitle: "General",
        rows: [
            MockRow(icon: "keyboard", iconBackground: .gray, title: "Keyboards", detail: "2", tapIndicator: true, emphasized: true),
            MockRow(icon: "textformat.abc", iconBackground: .gray, title: "Text Replacement"),
            MockRow(icon: "checkmark.circle", iconBackground: .gray, title: "Auto-Capitalization"),
            MockRow(icon: "abc", iconBackground: .gray, title: "Auto-Correction"),
            MockRow(icon: "keyboard.badge.ellipsis", iconBackground: .gray, title: "Predictive Text"),
            MockRow(icon: "rectangle.inset.filled.and.cursorarrow", iconBackground: .gray, title: "Slide to Type"),
        ]
    )

    static let addNewKeyboard = MockScreen(
        title: "Add New Keyboard",
        backTitle: "Keyboards",
        rows: [
            MockRow(icon: "keyboard.fill", iconBackground: .black, title: "Much Better Authenticator", trailingIcon: "checkmark", tapIndicator: true, emphasized: true),
            MockRow(icon: "abc", iconBackground: .blue, title: "English (US)"),
            MockRow(icon: "abc", iconBackground: .blue, title: "Emoji"),
            MockRow(icon: "globe", iconBackground: .blue, title: "Other Languages"),
            MockRow(icon: "keyboard", iconBackground: .gray, title: "Third-Party Keyboards"),
        ]
    )
}
