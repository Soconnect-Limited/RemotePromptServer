import Foundation

final class FileService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let maxFileSize: Int64 = 500_000 // 500KB

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Public APIs

    func listFiles(roomId: String, path: String, deviceId: String) async throws -> [FileItem] {
        var components = URLComponents(string: "\(Constants.baseURL)/rooms/\(roomId)/files")
        components?.queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "path", value: path),
        ]
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = try makeRequest(url: url, method: "GET")
        do {
            let (data, response) = try await session.data(for: request)
            try handleHTTPResponse(response, data: data)
            return try decoder.decode([FileItem].self, from: data)
        } catch let error as FileError {
            throw error
        } catch let urlError as URLError {
            throw FileError.networkError(urlError)
        }
    }

    func readFile(roomId: String, path: String, deviceId: String) async throws -> String {
        let encodedPath = encodePathSegment(path)
        guard let url = URL(string: "\(Constants.baseURL)/rooms/\(roomId)/files/\(encodedPath)?device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        var request = try makeRequest(url: url, method: "GET")
        do {
            let (data, response) = try await session.data(for: request)
            try handleHTTPResponse(response, data: data)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileError.serverError(500, "Invalid text encoding")
            }
            return text
        } catch let error as FileError {
            throw error
        } catch let urlError as URLError {
            throw FileError.networkError(urlError)
        }
    }

    func saveFile(roomId: String, path: String, content: String, deviceId: String) async throws {
        try validateFileSize(content)
        let encodedPath = encodePathSegment(path)
        guard let url = URL(string: "\(Constants.baseURL)/rooms/\(roomId)/files/\(encodedPath)?device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        var request = try makeRequest(url: url, method: "PUT")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = content.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            try handleHTTPResponse(response, data: data)
        } catch let error as FileError {
            throw error
        } catch let urlError as URLError {
            throw FileError.networkError(urlError)
        }
    }

    func validateFileSize(_ content: String) throws {
        let size = Int64(content.utf8.count)
        if size > maxFileSize {
            throw FileError.fileTooLarge(size)
        }
    }

    // MARK: - Helpers

    private func encodePathSegment(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return path
            .addingPercentEncoding(withAllowedCharacters: allowed)
            ?? path.replacingOccurrences(of: "/", with: "%2F")
    }

    private func makeRequest(url: URL, method: String) throws -> URLRequest {
        guard let apiKey = Constants.apiKey else {
            throw APIError.missingAPIKey
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }

    private func handleHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FileError.serverError(-1, "Invalid response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let detail = extractDetail(from: data)
            switch http.statusCode {
            case 400:
                throw FileError.invalidPath
            case 401:
                throw FileError.unauthorized
            case 403:
                throw FileError.forbidden
            case 404:
                throw FileError.serverError(404, detail ?? "File not found")
            case 413:
                throw FileError.fileTooLarge(maxFileSize)
            default:
                throw FileError.serverError(http.statusCode, detail ?? "Unknown error")
            }
        }
    }

    private func extractDetail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any] else { return nil }
        return dict["detail"] as? String
    }
}
