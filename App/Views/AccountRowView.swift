import SwiftUI

struct AccountRowView: View {
    let account: Account

    @State private var code: String = "------"
    @State private var secondsRemaining: Int = 30
    @State private var copied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var progress: Double {
        Double(secondsRemaining) / Double(account.period)
    }

    var timerColor: Color {
        if secondsRemaining <= 5 { return .red }
        if secondsRemaining <= 10 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: issuer icon + name + label + countdown
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(issuerColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Text(issuerInitial)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(issuerColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayIssuer)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(account.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Countdown ring
                ZStack {
                    Circle()
                        .stroke(timerColor.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(timerColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: secondsRemaining)
                    Text("\(secondsRemaining)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(timerColor)
                }
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)

            // Bottom: code + copy button
            HStack {
                Text(formattedCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(copied ? .green : .primary)
                    .tracking(2)

                Spacer()

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(copied ? .green : .blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(copied ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in
            updateCode()
        }
        .onAppear {
            updateCode()
        }
    }

    private func updateCode() {
        let now = Date()
        code = TOTPGenerator.generate(for: account, at: now) ?? "------"
        secondsRemaining = TOTPGenerator.secondsRemaining(period: account.period, at: now)
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }

    private var formattedCode: String {
        guard code.count >= 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[code.startIndex..<mid]) \(code[mid..<code.endIndex])"
    }

    private var displayIssuer: String {
        account.issuer.isEmpty
            ? (account.label.components(separatedBy: "@").last ?? "Account")
            : account.issuer
    }

    private var issuerInitial: String {
        String(displayIssuer.prefix(1)).uppercased()
    }

    private var issuerColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .mint]
        let hash = abs(account.issuer.hashValue)
        return colors[hash % colors.count]
    }
}
