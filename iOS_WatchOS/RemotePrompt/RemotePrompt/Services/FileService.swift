import Foundation

final class FileService {
    private let decoder: JSONDecoder
    private let maxFileSize: Int64 = 500_000 // 500KB

    /// APIClientと同じセッションを使用（証明書ピンニング対応）
    private var session: URLSession {
        APIClient.shared.sharedSession
    }

    init() {
        let decoder = JSONDecoder()
        // サーバーはISO8601形式（+00:00タイムゾーン付き）を返すためカスタムデコーダーを使用
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: dateString) {
                return date
            }

            // フラクショナルセカンドなしでも試す
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        self.decoder = decoder
    }

    // MARK: - Public APIs

    func listFiles(roomId: String, path: String, deviceId: String) async throws -> [FileItem] {
        let allURLs = Constants.allURLs
        guard !allURLs.isEmpty else { throw APIError.serverNotConfigured }

        var lastError: Error = APIError.invalidURL

        for baseURL in allURLs {
            do {
                var components = URLComponents(string: "\(baseURL)/rooms/\(roomId)/files")
                components?.queryItems = [
                    URLQueryItem(name: "device_id", value: deviceId),
                    URLQueryItem(name: "path", value: path),
                ]
                guard let url = components?.url else { continue }

                var request = try makeRequest(url: url, method: "GET")
                let (data, response) = try await session.data(for: request)
                try handleHTTPResponse(response, data: data)
                return try decoder.decode([FileItem].self, from: data)
            } catch let error as FileError {
                throw error  // FileErrorは即座にスロー（サーバーからの明確なエラー）
            } catch {
                lastError = error
                print("[FileService] listFiles failed for \(baseURL): \(error.localizedDescription)")
                continue  // 次のURLを試す
            }
        }
        throw lastError
    }

    func readFile(roomId: String, path: String, deviceId: String) async throws -> String {
        let allURLs = Constants.allURLs
        guard !allURLs.isEmpty else { throw APIError.serverNotConfigured }

        let encodedPath = encodePathSegment(path)
        var lastError: Error = APIError.invalidURL

        for baseURL in allURLs {
            do {
                guard let url = URL(string: "\(baseURL)/rooms/\(roomId)/files/\(encodedPath)?device_id=\(deviceId)") else {
                    continue
                }

                var request = try makeRequest(url: url, method: "GET")
                let (data, response) = try await session.data(for: request)
                try handleHTTPResponse(response, data: data)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw FileError.serverError(500, "Invalid text encoding")
                }
                return text
            } catch let error as FileError {
                throw error
            } catch {
                lastError = error
                print("[FileService] readFile failed for \(baseURL): \(error.localizedDescription)")
                continue
            }
        }
        throw lastError
    }

    func saveFile(roomId: String, path: String, content: String, deviceId: String) async throws {
        try validateFileSize(content)

        let allURLs = Constants.allURLs
        guard !allURLs.isEmpty else { throw APIError.serverNotConfigured }

        let encodedPath = encodePathSegment(path)
        var lastError: Error = APIError.invalidURL

        for baseURL in allURLs {
            do {
                guard let url = URL(string: "\(baseURL)/rooms/\(roomId)/files/\(encodedPath)?device_id=\(deviceId)") else {
                    continue
                }

                var request = try makeRequest(url: url, method: "PUT")
                request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = content.data(using: .utf8)

                let (data, response) = try await session.data(for: request)
                try handleHTTPResponse(response, data: data)
                return
            } catch let error as FileError {
                throw error
            } catch {
                lastError = error
                print("[FileService] saveFile failed for \(baseURL): \(error.localizedDescription)")
                continue
            }
        }
        throw lastError
    }

    func validateFileSize(_ content: String) throws {
        let size = Int64(content.utf8.count)
        if size > maxFileSize {
            throw FileError.fileTooLarge(size)
        }
    }

    /// PDFファイルをバイナリデータとして取得
    func readPDFFile(roomId: String, path: String, deviceId: String) async throws -> Data {
        let allURLs = Constants.allURLs
        guard !allURLs.isEmpty else { throw APIError.serverNotConfigured }

        let encodedPath = encodePathSegment(path)
        var lastError: Error = APIError.invalidURL

        for baseURL in allURLs {
            do {
                guard let url = URL(string: "\(baseURL)/rooms/\(roomId)/files/\(encodedPath)?device_id=\(deviceId)") else {
                    continue
                }

                var request = try makeRequest(url: url, method: "GET")
                let (data, response) = try await session.data(for: request)
                try handleHTTPResponse(response, data: data)
                return data
            } catch let error as FileError {
                throw error
            } catch {
                lastError = error
                print("[FileService] readPDFFile failed for \(baseURL): \(error.localizedDescription)")
                continue
            }
        }
        throw lastError
    }

    // MARK: - Helpers

    private func encodePathSegment(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        // パスセグメント中の '/' を %2F に必ずエンコードする（{filepath:path} で正しく解釈させるため）
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
