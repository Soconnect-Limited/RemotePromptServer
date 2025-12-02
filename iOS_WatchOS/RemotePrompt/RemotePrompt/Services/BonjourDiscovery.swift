import Foundation
import Network
import Combine

/// Bonjourサービス検出マネージャー
/// ローカルネットワーク上のRemotePromptサーバーを自動検出する
@MainActor
final class BonjourDiscovery: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var discoveredServers: [DiscoveredServer] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var error: Error?

    // MARK: - Private Properties

    private var browser: NWBrowser?
    private let serviceType = "_remoteprompt._tcp"

    // MARK: - Singleton

    static let shared = BonjourDiscovery()

    private init() {}

    // MARK: - Public Methods

    /// サーバー検索を開始
    func startSearching() {
        guard !isSearching else { return }

        discoveredServers.removeAll()
        error = nil
        isSearching = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateUpdate(state)
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleResultsChanged(results: results, changes: changes)
            }
        }

        browser?.start(queue: .main)
        print("[BonjourDiscovery] Started searching for \(serviceType)")
    }

    /// サーバー検索を停止
    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
        print("[BonjourDiscovery] Stopped searching")
    }

    /// 検出されたサーバーのアドレスを解決
    nonisolated func resolveServer(_ server: DiscoveredServer) async -> ResolvedServer? {
        return await withCheckedContinuation { continuation in
            let endpoint = server.endpoint

            let connection = NWConnection(to: endpoint, using: .tcp)
            var hasResumed = false

            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }

                switch state {
                case .ready:
                    // 接続成功 - エンドポイントからアドレスを取得
                    if let path = connection.currentPath,
                       let remoteEndpoint = path.remoteEndpoint {
                        let resolved = Self.extractAddressStatic(from: remoteEndpoint, server: server)
                        hasResumed = true
                        connection.cancel()
                        continuation.resume(returning: resolved)
                    } else {
                        hasResumed = true
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                case .failed, .cancelled:
                    hasResumed = true
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .main)

            // タイムアウト
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !hasResumed && connection.state != .ready {
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func handleStateUpdate(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("[BonjourDiscovery] Browser ready")
        case .failed(let error):
            print("[BonjourDiscovery] Browser failed: \(error)")
            self.error = error
            isSearching = false
        case .cancelled:
            isSearching = false
        default:
            break
        }
    }

    private func handleResultsChanged(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if let server = parseResult(result) {
                    if !discoveredServers.contains(where: { $0.id == server.id }) {
                        discoveredServers.append(server)
                        print("[BonjourDiscovery] Found server: \(server.name)")
                    }
                }
            case .removed(let result):
                if let server = parseResult(result) {
                    discoveredServers.removeAll { $0.id == server.id }
                    print("[BonjourDiscovery] Server removed: \(server.name)")
                }
            case .changed(old: _, new: let newResult, flags: _):
                if let server = parseResult(newResult) {
                    if let index = discoveredServers.firstIndex(where: { $0.id == server.id }) {
                        discoveredServers[index] = server
                    }
                }
            case .identical:
                // 変更なし
                break
            @unknown default:
                break
            }
        }
    }

    private func parseResult(_ result: NWBrowser.Result) -> DiscoveredServer? {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return nil
        }

        // TXTレコードからメタデータを取得
        var metadata = ServerMetadata()
        if case .bonjour(let txtRecord) = result.metadata {
            metadata = parseTextRecord(txtRecord)
        }

        return DiscoveredServer(
            id: "\(name).\(type).\(domain)",
            name: cleanServerName(name),
            endpoint: result.endpoint,
            metadata: metadata
        )
    }

    private func cleanServerName(_ name: String) -> String {
        // "RemotePrompt Server on hostname" -> "RemotePrompt Server on hostname"
        // サービス名の整形
        return name
            .replacingOccurrences(of: "._remoteprompt._tcp.local.", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func parseTextRecord(_ txtRecord: NWTXTRecord) -> ServerMetadata {
        var metadata = ServerMetadata()

        for key in ["version", "ssl_mode", "fingerprint", "path"] {
            if let value = txtRecord.getValue(for: key) {
                switch key {
                case "version":
                    metadata.version = value
                case "ssl_mode":
                    metadata.sslMode = value
                case "fingerprint":
                    metadata.fingerprint = value
                case "path":
                    metadata.path = value
                default:
                    break
                }
            }
        }

        return metadata
    }

    private func extractAddress(from endpoint: NWEndpoint, server: DiscoveredServer) -> ResolvedServer? {
        Self.extractAddressStatic(from: endpoint, server: server)
    }

    /// 静的メソッド版（nonisolatedコンテキストから呼び出し可能）
    private nonisolated static func extractAddressStatic(from endpoint: NWEndpoint, server: DiscoveredServer) -> ResolvedServer? {
        switch endpoint {
        case .hostPort(let host, let port):
            var ipAddress: String?
            switch host {
            case .ipv4(let address):
                ipAddress = "\(address)"
            case .ipv6(let address):
                ipAddress = "[\(address)]"
            case .name(let name, _):
                ipAddress = name
            @unknown default:
                break
            }

            guard let ip = ipAddress else { return nil }

            let portNumber = port.rawValue
            let url = "https://\(ip):\(portNumber)"

            return ResolvedServer(
                server: server,
                url: url,
                ipAddress: ip,
                port: Int(portNumber)
            )

        default:
            return nil
        }
    }
}

// MARK: - Data Models

/// 検出されたサーバー情報
struct DiscoveredServer: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let metadata: ServerMetadata

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.id == rhs.id
    }
}

/// サーバーのメタデータ（TXTレコードから取得）
struct ServerMetadata: Equatable {
    var version: String?
    var sslMode: String?
    var fingerprint: String?
    var path: String?
}

/// 解決済みサーバー情報（IPアドレス確定後）
struct ResolvedServer {
    let server: DiscoveredServer
    let url: String
    let ipAddress: String
    let port: Int
}

// MARK: - NWTXTRecord Extension

extension NWTXTRecord {
    func getValue(for key: String) -> String? {
        // NWTXTRecordのdictionaryは[String: String?]を返す
        if let value = self.dictionary[key] {
            return value
        }
        return nil
    }
}
