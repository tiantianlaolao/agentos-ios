import Foundation

@MainActor
@Observable
final class MemoryViewModel {
    var memoryText = ""
    var editText = ""
    var updatedAt: String?
    var isLoading = false
    var isSaving = false
    var isEditing = false
    var errorMessage = ""

    var charCount: Int { isEditing ? editText.count : memoryText.count }
    var hasChanges: Bool { editText != memoryText }

    private let service = MemoryAPIService.shared

    func loadMemory() async {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else { return }

        isLoading = true
        errorMessage = ""
        do {
            let data = try await service.getMemory(authToken: token)
            memoryText = data?.content ?? ""
            updatedAt = data?.updatedAt
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func startEditing() {
        editText = memoryText
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
    }

    func saveMemory() async {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else { return }

        isSaving = true
        errorMessage = ""
        do {
            let ok = try await service.saveMemory(content: editText, authToken: token)
            if ok {
                memoryText = editText
                updatedAt = ISO8601DateFormatter().string(from: Date())
                isEditing = false
            } else {
                errorMessage = "Save failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    var formattedUpdatedAt: String? {
        guard let updatedAt, !updatedAt.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: updatedAt) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: updatedAt) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return updatedAt
    }
}
