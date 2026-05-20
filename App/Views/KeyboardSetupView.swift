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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    stepsList
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Set up your keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.blue)
            }
            VStack(spacing: 6) {
                Text("Codes in any text field")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text("Enable the keyboard once. Then tap any 2FA code from the bar above the keyboard to insert it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private var stepsList: some View {
        VStack(spacing: 12) {
            stepRow(
                number: 1,
                icon: "gearshape.fill",
                iconColor: .gray,
                title: "Open iOS Settings",
                detail: "Tap the button below, or open Settings manually."
            )
            stepRow(
                number: 2,
                icon: "keyboard",
                iconColor: .blue,
                title: "General then Keyboard then Keyboards",
                detail: "Scroll down to Keyboards and tap it."
            )
            stepRow(
                number: 3,
                icon: "plus",
                iconColor: .green,
                title: "Tap Add New Keyboard",
                detail: "iOS shows a list of installed keyboards."
            )
            stepRow(
                number: 4,
                icon: "checkmark",
                iconColor: .green,
                title: "Select Much Better Authenticator",
                detail: "Done. Full Access is not required. The keyboard runs offline."
            )
        }
    }

    private func stepRow(
        number: Int,
        icon: String,
        iconColor: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary))
                    .offset(x: -2, y: -2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "arrow.up.right.square")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Text("Privacy: the keyboard runs offline. Codes are read from your iPhone's secure storage and never leave the device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
}
