import Foundation
import Security

/// The complete credential set persisted for one MAL account.
///
/// String representations are deliberately redacted so accidental interpolation cannot reveal
/// tokens in logs or errors.
struct MALStoredCredential: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let malUserID: Int

    var description: String {
        "MALStoredCredential(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

protocol MALCredentialDataStore: Sendable {
    func read() throws -> Data?
    func replace(with data: Data) throws
    func delete() throws
}

protocol MALInstallationMarkerStore: Sendable {
    func loadMarker() -> String?
    func saveMarker(_ marker: String)
}

enum MALCredentialStoreError: Error, LocalizedError, Equatable {
    case corruptRecord
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .corruptRecord:
            return "The saved MyAnimeList sign-in could not be read. Please sign in again."
        case .keychainFailure:
            return "The MyAnimeList sign-in could not be accessed securely. Please try again."
        }
    }
}

final class MALCredentialStore: @unchecked Sendable {
    private struct Record: Codable {
        static let currentVersion = 1

        let version: Int
        let credential: MALStoredCredential
    }

    private let dataStore: any MALCredentialDataStore
    private let markerStore: any MALInstallationMarkerStore
    private let makeMarker: @Sendable () -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        dataStore: any MALCredentialDataStore,
        markerStore: any MALInstallationMarkerStore,
        makeMarker: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.dataStore = dataStore
        self.markerStore = markerStore
        self.makeMarker = makeMarker
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() throws -> MALStoredCredential? {
        try protectAgainstReinstall()
        guard let data = try dataStore.read() else { return nil }

        do {
            let record = try decoder.decode(Record.self, from: data)
            guard record.version == Record.currentVersion else {
                throw MALCredentialStoreError.corruptRecord
            }
            return record.credential
        } catch let error as MALCredentialStoreError {
            throw error
        } catch {
            throw MALCredentialStoreError.corruptRecord
        }
    }

    func save(_ credential: MALStoredCredential) throws {
        try protectAgainstReinstall()
        let record = Record(version: Record.currentVersion, credential: credential)
        try dataStore.replace(with: encoder.encode(record))
    }

    func delete() throws {
        try protectAgainstReinstall()
        try dataStore.delete()
    }

    private func protectAgainstReinstall() throws {
        guard markerStore.loadMarker() == nil else { return }
        try dataStore.delete()
        markerStore.saveMarker(makeMarker())
    }
}

/// Production adapter storing one opaque, versioned record in the device-only Keychain.
struct MALKeychainCredentialDataStore: MALCredentialDataStore {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "MangaCarta",
        account: String = "myanimelist.oauth.credential"
    ) {
        self.service = service
        self.account = account
    }

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MALCredentialStoreError.keychainFailure(status: status) }
        guard let data = result as? Data else { throw MALCredentialStoreError.corruptRecord }
        return data
    }

    func replace(with data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MALCredentialStoreError.keychainFailure(status: updateStatus)
        }

        var addition = baseQuery
        attributes.forEach { addition[$0.key] = $0.value }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MALCredentialStoreError.keychainFailure(status: addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MALCredentialStoreError.keychainFailure(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class MALInMemoryCredentialDataStore: MALCredentialDataStore, @unchecked Sendable {
    enum Operation: Equatable {
        case read
        case replace
        case delete
    }

    private let lock = NSLock()
    private var storedData: Data?
    var failure: (operation: Operation, error: Error)?

    init(data: Data? = nil) {
        storedData = data
    }

    func read() throws -> Data? {
        try lock.withLock {
            if let failure, failure.operation == .read { throw failure.error }
            return storedData
        }
    }

    func replace(with data: Data) throws {
        try lock.withLock {
            if let failure, failure.operation == .replace { throw failure.error }
            storedData = data
        }
    }

    func delete() throws {
        try lock.withLock {
            if let failure, failure.operation == .delete { throw failure.error }
            storedData = nil
        }
    }
}

final class MALInMemoryInstallationMarkerStore: MALInstallationMarkerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var marker: String?

    init(marker: String? = nil) {
        self.marker = marker
    }

    func loadMarker() -> String? {
        lock.withLock { marker }
    }

    func saveMarker(_ marker: String) {
        lock.withLock { self.marker = marker }
    }

    func simulateReinstall() {
        lock.withLock { marker = nil }
    }
}

final class MALUserDefaultsInstallationMarkerStore: MALInstallationMarkerStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "mal.installation-marker") {
        self.defaults = defaults
        self.key = key
    }

    func loadMarker() -> String? {
        defaults.string(forKey: key)
    }

    func saveMarker(_ marker: String) {
        defaults.set(marker, forKey: key)
    }
}
