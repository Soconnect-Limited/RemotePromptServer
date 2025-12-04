import Foundation

/// ローカライズ用のString Extension
extension String {
    /// ローカライズされた文字列を返す
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// 引数付きローカライズ
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}

/// ローカライズキー定義
enum L10n {
    // MARK: - Common
    enum Common {
        static var cancel: String { "common.cancel".localized }
        static var save: String { "common.save".localized }
        static var delete: String { "common.delete".localized }
        static var edit: String { "common.edit".localized }
        static var done: String { "common.done".localized }
        static var close: String { "common.close".localized }
        static var ok: String { "common.ok".localized }
        static var error: String { "common.error".localized }
        static var loading: String { "common.loading".localized }
        static var create: String { "common.create".localized }
        static var reset: String { "common.reset".localized }
        static var openSettings: String { "common.openSettings".localized }
    }

    // MARK: - Rooms
    enum Rooms {
        static var title: String { "rooms.title".localized }
        static var empty: String { "rooms.empty".localized }
        static var emptyHint: String { "rooms.empty.hint".localized }
        static var deleteTitle: String { "rooms.delete.title".localized }
        static func deleteMessage(_ name: String) -> String {
            "rooms.delete.message".localized(name)
        }
    }

    // MARK: - Room Create/Edit
    enum Room {
        static var createTitle: String { "room.create.title".localized }
        static var editTitle: String { "room.edit.title".localized }
        static var fieldName: String { "room.field.name".localized }
        static var fieldWorkspace: String { "room.field.workspace".localized }
        static var fieldIcon: String { "room.field.icon".localized }
        static var sectionBasic: String { "room.section.basic".localized }
    }

    // MARK: - Threads
    enum Threads {
        static var title: String { "threads.title".localized }
        static var empty: String { "threads.empty".localized }
        static var new: String { "threads.new".localized }
        static var createTitle: String { "threads.create.title".localized }
        static var createHint: String { "threads.create.hint".localized }
        static var editTitle: String { "threads.edit.title".localized }
        static var fieldName: String { "threads.field.name".localized }
        static var untitled: String { "threads.untitled".localized }
        static var lastConversation: String { "threads.lastConversation".localized }
        static var noHistory: String { "threads.noHistory".localized }
        static func fetchError(_ error: String) -> String {
            "threads.fetch.error".localized(error)
        }
        static func createError(_ error: String) -> String {
            "threads.create.error".localized(error)
        }
        static func updateError(_ error: String) -> String {
            "threads.update.error".localized(error)
        }
        static func deleteError(_ error: String) -> String {
            "threads.delete.error".localized(error)
        }
    }

    // MARK: - Chat
    enum Chat {
        static var placeholder: String { "chat.input.placeholder".localized }
        static var generating: String { "chat.generating".localized }
        static var cancel: String { "chat.cancel".localized }
        static var cancelled: String { "chat.cancelled".localized }
        static var timeout: String { "chat.timeout".localized }
        static var readMore: String { "chat.readMore".localized }
        static var collapse: String { "chat.collapse".localized }
        static func recoveryFailed(_ error: String) -> String {
            "chat.recovery.failed".localized(error)
        }
    }

    // MARK: - Server Settings
    enum Settings {
        static var serverTitle: String { "settings.server.title".localized }
        static var serverUrl: String { "settings.server.url".localized }
        static var serverUrlPlaceholder: String { "settings.server.url.placeholder".localized }
        static var serverUrlHint: String { "settings.server.url.hint".localized }
        static var serverUrlInvalid: String { "settings.server.url.invalid".localized }
        static var apiKey: String { "settings.server.apikey".localized }
        static var apiKeyPlaceholder: String { "settings.server.apikey.placeholder".localized }
        static var apiKeyHint: String { "settings.server.apikey.hint".localized }
        static var sectionInfo: String { "settings.server.section.info".localized }
        static var sectionAuth: String { "settings.server.section.auth".localized }
        static var sectionConnection: String { "settings.server.section.connection".localized }
        static var sectionCertificate: String { "settings.server.section.certificate".localized }
        static var sectionAI: String { "settings.server.section.ai".localized }
        static var sectionAdvanced: String { "settings.server.section.advanced".localized }
        static var aiSortHint: String { "settings.ai.sort.hint".localized }
        static var resetCertificate: String { "settings.reset.certificate".localized }
        static var resetAll: String { "settings.reset.all".localized }
        static var resetAllTitle: String { "settings.reset.all.title".localized }
        static var resetAllConfirm: String { "settings.reset.all.confirm".localized }

        static func runnerSettings(_ runner: String) -> String {
            switch runner {
            case "claude": return "settings.claude".localized
            case "codex": return "settings.codex".localized
            case "gemini": return "settings.gemini".localized
            default: return "settings.runner".localized(runner)
            }
        }
    }

    // MARK: - Connection
    enum Connection {
        static var test: String { "connection.test".localized }
        static var idle: String { "connection.status.idle".localized }
        static var testing: String { "connection.status.testing".localized }
        static var success: String { "connection.status.success".localized }
        static var failedAll: String { "connection.failed.all".localized }
    }

    // MARK: - Alternative URLs
    enum AltUrl {
        static var title: String { "settings.alturl.title".localized }
        static var toggle: String { "settings.alturl.toggle".localized }
        static var hint: String { "settings.alturl.hint".localized }
        static var placeholder: String { "settings.alturl.placeholder".localized }
    }

    // MARK: - Certificate
    enum Certificate {
        static var title: String { "certificate.title".localized }
        static var changedTitle: String { "certificate.changed.title".localized }
        static var revokedTitle: String { "certificate.revoked.title".localized }
        static var modeChangedTitle: String { "certificate.mode.changed.title".localized }
        static var errorTitle: String { "certificate.error.title".localized }
        static var trust: String { "certificate.trust".localized }
        static var trustNew: String { "certificate.trust.new".localized }
        static var reconnect: String { "certificate.reconnect".localized }
        static var reset: String { "certificate.reset".localized }
        static var resetConfirm: String { "certificate.reset.confirm".localized }
        static var fingerprint: String { "certificate.fingerprint".localized }
        static var commonName: String { "certificate.commonName".localized }
        static var validUntil: String { "certificate.validUntil".localized }
        static var selfSigned: String { "certificate.selfSigned".localized }
        static var commercial: String { "certificate.commercial".localized }
        static var newPending: String { "certificate.new.pending".localized }
        static var newPendingHint: String { "certificate.new.pending.hint".localized }
        static var verifyFailed: String { "certificate.verify.failed".localized }
        static var verifyHint: String { "certificate.verify.hint".localized }
        static var changedWarning: String { "certificate.changed.warning".localized }
        static var trustConnect: String { "certificate.trust.connect".localized }
        static var cancelConnection: String { "certificate.cancel.connection".localized }
        static var discardSaved: String { "certificate.discard.saved".localized }
        static var sha256: String { "certificate.sha256".localized }
        static var oldFingerprint: String { "certificate.old.fingerprint".localized }
        static var newFingerprint: String { "certificate.new.fingerprint".localized }
        static var mitm: String { "certificate.mitm".localized }
        static var contactAdmin: String { "certificate.contact.admin".localized }

        static func changedDetail(old: String, new: String) -> String {
            "certificate.changed.detail".localized(old, new)
        }
        static func mismatchMessage(stored: String, received: String) -> String {
            "certificate.mismatch.message".localized(stored, received)
        }
        static func updatedRestart(_ reason: String) -> String {
            "certificate.updated.restart".localized(reason)
        }
        static func updatedReconnect(_ reason: String) -> String {
            "certificate.updated.reconnect".localized(reason)
        }
        static func revokedMessage(_ reason: String) -> String {
            "certificate.revoked.message".localized(reason)
        }
        static func modeChangedMessage(from: String, to: String, reason: String) -> String {
            "certificate.mode.changed.message".localized(from, to, reason)
        }
    }

    // MARK: - Welcome
    enum Welcome {
        static var title: String { "welcome.title".localized }
        static var hint: String { "welcome.hint".localized }
        static var setup: String { "welcome.setup".localized }
    }

    // MARK: - QR Code
    enum QR {
        static var shareTitle: String { "qr.share.title".localized }
        static var shareHint: String { "qr.share.hint".localized }
        static var shareInfo: String { "qr.share.info".localized }
        static var shareServerUrl: String { "qr.share.serverUrl".localized }
        static var shareDeviceId: String { "qr.share.deviceId".localized }
        static var shareAltUrls: String { "qr.share.altUrls".localized }
        static func shareAltUrlsCount(_ count: Int) -> String {
            "qr.share.altUrls.count".localized(count)
        }
        static var generateFailed: String { "qr.generate.failed".localized }
        static var importTitle: String { "qr.import.title".localized }
        static var importHint: String { "qr.import.hint".localized }
        static func importConfirm(server: String, deviceId: String) -> String {
            "qr.import.confirm".localized(server, deviceId)
        }
        static var importButton: String { "qr.import.button".localized }
        static var invalid: String { "qr.invalid".localized }
        static var unknownError: String { "qr.unknown.error".localized }
    }

    // MARK: - Camera
    enum Camera {
        static var accessDenied: String { "camera.access.denied".localized }
        static var inputFailed: String { "camera.input.failed".localized }
        static var metadataFailed: String { "camera.metadata.failed".localized }
    }

    // MARK: - Bonjour
    enum Bonjour {
        static var searching: String { "bonjour.searching".localized }
        static var notfound: String { "bonjour.notfound".localized }
        static var search: String { "bonjour.search".localized }
        static var stop: String { "bonjour.stop".localized }
        static var auto: String { "bonjour.auto".localized }
        static var hint: String { "bonjour.hint".localized }
    }

    // MARK: - Room Settings
    enum RoomSettings {
        static func sendValue(_ value: String) -> String {
            "roomsettings.sendValue".localized(value)
        }
        static var resetDefault: String { "roomsettings.resetDefault".localized }
    }

    // MARK: - Editor
    enum Editor {
        static var save: String { "editor.save".localized }
        static var saveSuccess: String { "editor.save.success".localized }
        static var saveError: String { "editor.save.error".localized }
    }

    // MARK: - Files
    enum Files {
        static var empty: String { "files.empty".localized }
        static var copyPath: String { "files.copy.path".localized }
        static var retry: String { "files.retry".localized }
        static var unknownError: String { "files.error.unknown".localized }
        static func sizeError(_ size: String) -> String {
            "file.error.size".localized(size)
        }
        static var pathError: String { "file.error.path".localized }
        static var authError: String { "file.error.auth".localized }
        static var permissionError: String { "file.error.permission".localized }
        static var networkError: String { "file.error.network".localized }
        static func serverError(_ code: Int, _ detail: String) -> String {
            "file.error.server".localized(code, detail)
        }
    }

    // MARK: - Device ID
    enum DeviceId {
        static var editTitle: String { "deviceId.edit.title".localized }
        static var editHint: String { "deviceId.edit.hint".localized }
        static var editPlaceholder: String { "deviceId.edit.placeholder".localized }
        static var editConfirm: String { "deviceId.edit.confirm".localized }
        static var editButton: String { "deviceId.edit.button".localized }
        static var current: String { "deviceId.current".localized }
    }

    // MARK: - Errors
    enum Error {
        static var invalidUrl: String { "error.invalidUrl".localized }
        static var apiKeyMissing: String { "error.apikey.missing".localized }
        static func network(_ message: String) -> String {
            "error.network".localized(message)
        }
        static func certificate(_ message: String) -> String {
            "error.certificate".localized(message)
        }
        static var auth: String { "error.auth".localized }
        static func server(_ code: Int) -> String {
            "error.server".localized(code)
        }
        static func unknown(_ message: String) -> String {
            "error.unknown".localized(message)
        }
    }
}
