import SwiftUI

struct ManualEntryView: View {
    let onSave: (Account) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var label = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Issuer (e.g. GitHub)", text: $issuer)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()
                    TextField("Label (e.g. user@email.com)", text: $label)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Secret Key") {
                    TextField("Base32 secret key", text: $secret)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("Advanced") {
                    Picker("Algorithm", selection: $algorithm) {
                        ForEach(OTPAlgorithm.allCases, id: \.self) { algo in
                            Text(algo.rawValue).tag(algo)
                        }
                    }
                    Picker("Digits", selection: $digits) {
                        Text("6").tag(6)
                        Text("7").tag(7)
                        Text("8").tag(8)
                    }
                    Picker("Period", selection: $period) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(secret.isEmpty)
                }
            }
        }
    }

    private func save() {
        let cleanSecret = secret
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard Base32.decode(cleanSecret) != nil else {
            error = "Invalid Base32 secret key"
            return
        }

        let account = Account(
            issuer: issuer.isEmpty ? "Unknown" : issuer,
            label: label.isEmpty ? issuer : label,
            secret: cleanSecret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )

        onSave(account)
    }
}
