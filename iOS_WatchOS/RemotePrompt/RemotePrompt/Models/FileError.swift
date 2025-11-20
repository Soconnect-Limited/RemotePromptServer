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
            return "ファイルサイズが上限(500KB)を超えています: \(formatted)"
        case .invalidPath:
            return "不正なファイルパスです"
        case .unauthorized:
            return "認証に失敗しました"
        case .forbidden:
            return "このルームにアクセスする権限がありません"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .serverError(let code, let detail):
            return "サーバーエラー(\(code)): \(detail)"
        }
    }
}
