import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .httpError(let code):
            return "サーバーエラー(\(code))"
        }
    }
}

struct CreateJobRequest: Codable {
    let runner: String
    let inputText: String
    let deviceId: String
    let notifyToken: String?

    enum CodingKeys: String, CodingKey {
        case runner
        case inputText = "input_text"
        case deviceId = "device_id"
        case notifyToken = "notify_token"
    }
}

struct CreateJobResponse: Codable {
    let id: String
    let runner: String
    let status: String
}

final class APIClient {
    static let shared = APIClient()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchJob(id: String) async throws -> Job {
        guard let url = URL(string: "\(Constants.baseURL)/jobs/\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey = Constants.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(code)
        }

        return try decoder.decode(Job.self, from: data)
    }

    func createJob(runner: String, prompt: String, deviceId: String) async throws -> CreateJobResponse {
        guard let url = URL(string: "\(Constants.baseURL)/jobs") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey = Constants.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateJobRequest(
            runner: runner,
            inputText: prompt,
            deviceId: deviceId,
            notifyToken: nil
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(code)
        }

        return try decoder.decode(CreateJobResponse.self, from: data)
    }

    static func getDeviceId() -> String {
        if let saved = UserDefaults.standard.string(forKey: "remote_prompt_device_id") {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "remote_prompt_device_id")
        return newId
    }
}
