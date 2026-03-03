import Foundation

actor UploadService {
    static let shared = UploadService()

    private let serverBaseURL = "http://43.155.104.45:3100"

    func upload(data: Data, fileName: String, mimeType: String, authToken: String? = nil, deviceId: String? = nil) async throws -> Attachment {
        let url = URL(string: "\(serverBaseURL)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let deviceId = deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UploadError.serverError
        }

        struct UploadResponse: Codable {
            let id: String
            let url: String
            let name: String
            let size: Int
            let mimeType: String
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)

        return Attachment(
            id: uploadResponse.id,
            type: mimeType.hasPrefix("image/") ? .image : .file,
            url: uploadResponse.url,
            name: uploadResponse.name,
            size: uploadResponse.size,
            mimeType: uploadResponse.mimeType
        )
    }

    func fullURL(for attachment: Attachment) -> URL? {
        URL(string: "\(serverBaseURL)\(attachment.url)")
    }

    enum UploadError: Error, LocalizedError {
        case serverError
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .serverError: return "Upload failed"
            case .invalidResponse: return "Invalid server response"
            }
        }
    }
}
