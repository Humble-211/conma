import SwiftUI
import DesignSystem

struct DatabaseErrorView: View {
    let error: Error
    let databaseURL: URL
    let retry: () -> Void

    private var existingFiles: [URL] {
        [databaseURL, URL(fileURLWithPath: databaseURL.path + "-wal"), URL(fileURLWithPath: databaseURL.path + "-shm")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            EmptyState(systemImage: "externaldrive.badge.exclamationmark", title: "error.database.title", message: "error.database.message")
            Text(verbatim: String(describing: error)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg)
            VStack(spacing: DSSpacing.md) {
                PrimaryButton("error.database.retry", systemImage: "arrow.clockwise", action: retry)
                if !existingFiles.isEmpty {
                    ShareLink(items: existingFiles) {
                        Label("error.database.export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.bottom, DSSpacing.xl)
        .background(DSColor.background)
    }
}
