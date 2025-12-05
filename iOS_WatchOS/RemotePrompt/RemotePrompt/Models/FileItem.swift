import Foundation

struct FileItem: Identifiable, Codable, Hashable {
    let id: String  // = path
    let name: String
    let type: FileType
    let path: String
    let size: Int64?
    let modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case path
        case size
        case modifiedAt = "modified_at"
    }
}

enum FileType: String, Codable {
    case directory
    case markdownFile = "markdown_file"
    case pdfFile = "pdf_file"
    case imageFile = "image_file"
}
