import Foundation

enum FileError: LocalizedError {
    case fileTooLarge(Int64)
    case invalidPath
    case unauthorized
    case forbidden
    case networkError(Error)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            let formatted = formatter.string(fromByteCount: size)
            return L10n.Files.sizeError(formatted)
        case .invalidPath:
            return L10n.Files.pathError
        case .unauthorized:
            return L10n.Files.authError
        case .forbidden:
            return L10n.Files.permissionError
        case .networkError:
            return L10n.Files.networkError
        case .serverError(let code, let detail):
            return L10n.Files.serverError(code, detail)
        }
    }
}
