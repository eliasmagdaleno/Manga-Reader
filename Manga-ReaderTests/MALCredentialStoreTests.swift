import Foundation
import Security
import Testing
@testable import Manga_Reader

@Suite("MAL credential storage")
struct MALCredentialStoreTests {
    private let credential = MALStoredCredential(
        tokenType: "Bearer",
        accessToken: "access-secret",
        refreshToken: "refresh-secret",
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        malUserID: 42
    )

    @Test("First install creates a marker and starts signed out")
    func firstInstall() throws {
        let dataStore = MALInMemoryCredentialDataStore()
        let markers = MALInMemoryInstallationMarkerStore()
        let store = makeStore(dataStore: dataStore, markers: markers)

        #expect(try store.load() == nil)
        #expect(markers.loadMarker() == "installation-1")
    }

    @Test("Ordinary relaunch preserves the complete credential")
    func ordinaryRelaunch() throws {
        let dataStore = MALInMemoryCredentialDataStore()
        let markers = MALInMemoryInstallationMarkerStore(marker: "installation-1")
        try makeStore(dataStore: dataStore, markers: markers).save(credential)

        let relaunchedStore = makeStore(dataStore: dataStore, markers: markers)
        #expect(try relaunchedStore.load() == credential)
    }

    @Test("Simulated reinstall deletes a credential that survived in Keychain")
    func simulatedReinstall() throws {
        let dataStore = MALInMemoryCredentialDataStore()
        let markers = MALInMemoryInstallationMarkerStore(marker: "installation-1")
        let oldStore = makeStore(dataStore: dataStore, markers: markers)
        try oldStore.save(credential)
        markers.simulateReinstall()

        let reinstalledStore = makeStore(dataStore: dataStore, markers: markers)
        #expect(try reinstalledStore.load() == nil)
        #expect(markers.loadMarker() == "installation-1")
    }

    @Test("Corrupt records produce a sanitized presentation error")
    func corruptRecord() throws {
        let dataStore = MALInMemoryCredentialDataStore(data: Data("not-json".utf8))
        let store = makeStore(dataStore: dataStore)

        #expect {
            try store.load()
        } throws: { error in
            error as? MALCredentialStoreError == .corruptRecord
        }
        #expect(MALCredentialStoreError.corruptRecord.localizedDescription.contains("access-secret") == false)
    }

    @Test("Logout deletes the saved credential")
    func logoutDeletion() throws {
        let store = makeStore()
        try store.save(credential)
        try store.delete()

        #expect(try store.load() == nil)
    }

    @Test("Failed replacement leaves the old complete credential readable")
    func failedTransactionalReplacement() throws {
        let dataStore = MALInMemoryCredentialDataStore()
        let store = makeStore(dataStore: dataStore)
        try store.save(credential)
        dataStore.failure = (.replace, MALCredentialStoreError.keychainFailure(status: errSecIO))

        let replacement = MALStoredCredential(
            tokenType: "Bearer",
            accessToken: "new-access-secret",
            refreshToken: "new-refresh-secret",
            expiresAt: credential.expiresAt.addingTimeInterval(100),
            malUserID: credential.malUserID
        )
        #expect(throws: MALCredentialStoreError.self) { try store.save(replacement) }
        dataStore.failure = nil
        #expect(try store.load() == credential)
    }

    @Test("Successful replacement exposes only the new complete credential")
    func successfulTransactionalReplacement() throws {
        let store = makeStore()
        try store.save(credential)
        let replacement = MALStoredCredential(
            tokenType: "Bearer",
            accessToken: "new-access-secret",
            refreshToken: "new-refresh-secret",
            expiresAt: credential.expiresAt.addingTimeInterval(100),
            malUserID: 99
        )

        try store.save(replacement)
        #expect(try store.load() == replacement)
    }

    @Test("Keychain errors are presented without status details or secrets")
    func keychainErrorPresentation() {
        let error = MALCredentialStoreError.keychainFailure(status: errSecAuthFailed)
        let presentation = error.localizedDescription

        #expect(presentation == "The MyAnimeList sign-in could not be accessed securely. Please try again.")
        #expect(presentation.contains("access-secret") == false)
        #expect(presentation.contains(String(errSecAuthFailed)) == false)
    }

    @Test("Credential string representations redact tokens")
    func credentialDescriptionsAreRedacted() {
        let descriptions = [String(describing: credential), String(reflecting: credential)]

        for description in descriptions {
            #expect(description.contains(credential.accessToken) == false)
            #expect(description.contains(credential.refreshToken) == false)
            #expect(description.contains("<redacted>"))
        }
    }

    @Test("A failed reinstall cleanup does not bless the installation marker")
    func failedReinstallCleanupRetries() throws {
        let dataStore = MALInMemoryCredentialDataStore()
        let markers = MALInMemoryInstallationMarkerStore(marker: "old-installation")
        let store = makeStore(dataStore: dataStore, markers: markers)
        try store.save(credential)
        markers.simulateReinstall()
        dataStore.failure = (.delete, MALCredentialStoreError.keychainFailure(status: errSecIO))

        #expect(throws: MALCredentialStoreError.self) { try store.load() }
        #expect(markers.loadMarker() == nil)
        dataStore.failure = nil
        #expect(try store.load() == nil)
    }

    private func makeStore(
        dataStore: MALInMemoryCredentialDataStore = MALInMemoryCredentialDataStore(),
        markers: MALInMemoryInstallationMarkerStore = MALInMemoryInstallationMarkerStore(
            marker: "installation-1"
        )
    ) -> MALCredentialStore {
        MALCredentialStore(dataStore: dataStore, markerStore: markers) { "installation-1" }
    }
}
