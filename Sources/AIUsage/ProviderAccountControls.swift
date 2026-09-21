import SwiftUI

/// Shared account-name editor for Claude and Codex profile rows.
struct AccountNicknameField: View {
    @Binding var text: String
    let plan: String?
    let hasChanges: Bool
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nickname")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Glass.ink(0.48))

            HStack(spacing: 8) {
                TextField("Account nickname", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(isFocused ? 0.28 : 0.14))
                    )
                    .focused($isFocused)
                    .onSubmit {
                        onCommit()
                        isFocused = false
                    }

                if let plan, !plan.isEmpty {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Glass.ink(0.5))
                }

                GlassButton(
                    label: "Save",
                    prominent: true,
                    enabled: hasChanges
                ) {
                    onCommit()
                    isFocused = false
                }
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { onCommit() }
        }
        .onDisappear { onCommit() }
    }
}
