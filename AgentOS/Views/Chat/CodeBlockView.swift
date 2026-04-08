import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: language label + copy button
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(AppTheme.smallFont)
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = code
                    #endif
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy")
                            .font(AppTheme.smallFont)
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.paddingStandard)
            .padding(.vertical, AppTheme.paddingSmall)
            .background(AppTheme.border)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "#2D2620"))
                    .padding(AppTheme.paddingStandard)
            }
        }
        .background(AppTheme.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}
