//
//  MALAccountStore.swift
//  Manga-Reader
//
//  The observable MyAnimeList account: one explicit state, the sign-in flow that moves
//  through it, and the local sign-out that takes the account's data with it.
//
//  Sign-in is optional and nothing here is on the reading path. Tokens live in the Keychain
//  (`MALCredentialStore`); only the non-secret profile cache and the two sync preferences are
//  stored here.
//

import Foundation

/// The non-secret account cache. Safe to keep outside the Keychain: a display name and an
/// avatar URL are presentation data, and the two switches are preferences.
struct MALAccountPreferences: Codable, Equatable, Sendable {
    var profile: MALUserIdentity
    var syncEnabled: Bool
    var automaticallyAddsTitles: Bool
}

protocol MALAccountPreferenceStore: AnyObject, Sendable {
    func load() -> MALAccountPreferences?
    func save(_ preferences: MALAccountPreferences)
    func clear()
    /// Whose queued updates are still on disk. Deliberately outlives `clear()`: a sign-out
    /// must not silently orphan another account's queue.
    func loadQueuedAccountUserID() -> Int?
    func saveQueuedAccountUserID(_ userID: Int?)
}

/// A pending question for the user: signing in as a different MAL account leaves the previous
/// account's queued updates on disk, and they are deleted only if the user says so.
struct MALAccountSwitchRequest: Equatable, Sendable {
    let previousUserID: Int
    let pendingCount: Int
}

@MainActor
final class MALAccountStore: ObservableObject {
    /// The one explicit account state. `error` keeps the stable state it interrupted, so a
    /// dismissed message returns the UI exactly where it was.
    indirect enum State: Equatable {
        case signedOut
        case authorizing
        case signedIn(profile: MALUserIdentity, syncEnabled: Bool, automaticallyAddsTitles: Bool)
        case refreshing(profile: MALUserIdentity)
        case reauthorizationRequired(profile: MALUserIdentity?)
        case error(message: String, previousStable: State)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var pendingAccountSwitch: MALAccountSwitchRequest?

    private let configuration: MALOAuthConfiguration
    private let presenter: any MALAuthPresenting
    private let tokenClient: MALTokenClient
    private let credentials: MALCredentialStore
    private let preferences: any MALAccountPreferenceStore
    private let outbox: any MALProgressOutboxProtocol
    private let fetchIdentity: @Sendable (String) async throws -> MALUserIdentity
    private let now: @Sendable () -> Date
    private let makeVerifier: @Sendable () -> String
    private let makeState: @Sendable () -> String

    /// Non-nil exactly while a sign-in is in flight, so a second tap joins it rather than
    /// opening a second web sheet.
    private var signInTask: Task<Void, Never>?

    init(
        configuration: MALOAuthConfiguration,
        presenter: any MALAuthPresenting,
        tokenClient: MALTokenClient,
        credentials: MALCredentialStore,
        preferences: any MALAccountPreferenceStore,
        outbox: any MALProgressOutboxProtocol,
        fetchIdentity: @escaping @Sendable (String) async throws -> MALUserIdentity,
        now: @escaping @Sendable () -> Date = { Date() },
        makeVerifier: @escaping @Sendable () -> String = {
            MALPKCE.makeVerifier(randomBytes: MALAccountStore.randomBytes)
        },
        makeState: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.configuration = configuration
        self.presenter = presenter
        self.tokenClient = tokenClient
        self.credentials = credentials
        self.preferences = preferences
        self.outbox = outbox
        self.fetchIdentity = fetchIdentity
        self.now = now
        self.makeVerifier = makeVerifier
        self.makeState = makeState
    }

    // MARK: Lifecycle

    /// Rebuilds the state at launch from what is on disk. A cached profile whose credential
    /// is gone is `reauthorizationRequired`, not a silent sign-out: the user believes they
    /// are signed in, and their queued work is still theirs.
    func restore() {
        guard let cached = preferences.load() else {
            state = .signedOut
            return
        }
        let credential = try? credentials.load()
        guard credential != nil else {
            state = .reauthorizationRequired(profile: cached.profile)
            return
        }
        state = .signedIn(profile: cached.profile,
                          syncEnabled: cached.syncEnabled,
                          automaticallyAddsTitles: cached.automaticallyAddsTitles)
    }

    /// Marks the account as needing a fresh sign-in. Called when a request comes back
    /// `reauthorizationRequired`; the queue is retained, and local reading is unaffected.
    func reauthorizationRequired() {
        state = .reauthorizationRequired(profile: currentProfile)
    }

    // MARK: Sign-in

    func signIn() async {
        let task: Task<Void, Never>
        if let signInTask {
            task = signInTask
        } else {
            task = Task { await performSignIn() }
            signInTask = task
        }
        // The sign-in runs in an unstructured task so a second tap can join it. That means
        // cancelling the caller does not cancel it on its own — this hands the cancellation
        // across, or a cancelled sign-in would keep a web sheet alive behind the user.
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if signInTask == task { signInTask = nil }
    }

    private func performSignIn() async {
        let stable = stableState
        state = .authorizing

        let verifier = makeVerifier()
        let session = MALOAuthSession(configuration: configuration,
                                      state: makeState(),
                                      verifier: verifier)

        let callback: URL
        do {
            callback = try await presenter.authenticate(
                url: session.authorizationURL,
                callbackScheme: Self.callbackScheme(from: configuration.redirectURI)
            )
        } catch MALAuthPresentationError.cancelled {
            // Declining is not a failure and gets no error message.
            state = stable
            return
        } catch is CancellationError {
            state = stable
            return
        } catch {
            state = .error(message: Self.signInFailureMessage, previousStable: stable)
            return
        }

        if Task.isCancelled {
            state = stable
            return
        }

        let code: String
        switch session.complete(with: callback) {
        case let .code(value):
            code = value
        case .cancelled:
            state = stable
            return
        case .failed, .rejected:
            state = .error(message: Self.signInFailureMessage, previousStable: stable)
            return
        }

        do {
            let credential = try await tokenClient.fetch(session.exchange(code: code))
            // The identity read comes before anything is persisted: a credential is stored
            // only once it is known whose it is.
            let profile = try await fetchIdentity(credential.accessToken)
            try adopt(credential: credential, profile: profile)
        } catch is CancellationError {
            state = stable
        } catch {
            state = .error(message: Self.signInFailureMessage, previousStable: stable)
        }
    }

    private func adopt(credential: MALCredential, profile: MALUserIdentity) throws {
        try credentials.save(MALStoredCredential(tokenType: credential.tokenType,
                                                 accessToken: credential.accessToken,
                                                 refreshToken: credential.refreshToken,
                                                 expiresAt: credential.expiresAt,
                                                 malUserID: profile.id))

        // Sync and automatic addition default on for a new account, and a reauthorization of
        // the same account keeps whatever the user last chose.
        let existing = preferences.load()
        let carried = existing?.profile.id == profile.id ? existing : nil
        let record = MALAccountPreferences(
            profile: profile,
            syncEnabled: carried?.syncEnabled ?? true,
            automaticallyAddsTitles: carried?.automaticallyAddsTitles ?? true
        )
        preferences.save(record)

        let queuedOwner = preferences.loadQueuedAccountUserID()
        if let queuedOwner, queuedOwner != profile.id {
            // Another account's updates are still queued. They are never sent to this
            // account, and they are deleted only if the user confirms it.
            pendingAccountSwitch = MALAccountSwitchRequest(
                previousUserID: queuedOwner,
                pendingCount: outbox.summary(userID: queuedOwner).pending
            )
        } else {
            pendingAccountSwitch = nil
            preferences.saveQueuedAccountUserID(profile.id)
        }

        state = .signedIn(profile: record.profile,
                          syncEnabled: record.syncEnabled,
                          automaticallyAddsTitles: record.automaticallyAddsTitles)
    }

    // MARK: Account switching

    /// Deletes the previous account's queued updates. Only ever called from an explicit
    /// confirmation.
    func confirmAccountSwitchDeletion() throws {
        guard let request = pendingAccountSwitch else { return }
        try outbox.clear(userID: request.previousUserID)
        pendingAccountSwitch = nil
        if case let .signedIn(profile, _, _) = state {
            preferences.saveQueuedAccountUserID(profile.id)
        }
    }

    /// Leaves the previous account's queue alone. It is not drained — the drain is keyed by
    /// the signed-in user — but it stays recoverable if that account signs in again.
    func dismissAccountSwitch() {
        pendingAccountSwitch = nil
    }

    // MARK: Preferences

    func setSyncEnabled(_ enabled: Bool) {
        update { $0.syncEnabled = enabled }
    }

    func setAutomaticallyAddsTitles(_ enabled: Bool) {
        update { $0.automaticallyAddsTitles = enabled }
    }

    private func update(_ change: (inout MALAccountPreferences) -> Void) {
        guard var record = preferences.load() else { return }
        change(&record)
        preferences.save(record)
        state = .signedIn(profile: record.profile,
                          syncEnabled: record.syncEnabled,
                          automaticallyAddsTitles: record.automaticallyAddsTitles)
    }

    // MARK: Sign-out

    /// Sign out **on this device**: MAL publishes no revocation endpoint, so this deletes
    /// local account data and nothing else. History, Library, and Works are untouched — they
    /// are the user's own reading, not account data.
    func signOut() throws {
        signInTask?.cancel()
        signInTask = nil
        pendingAccountSwitch = nil

        let userID = (try? credentials.load())??.malUserID
        try credentials.delete()
        preferences.clear()
        if let userID {
            try outbox.clear(userID: userID)
            preferences.saveQueuedAccountUserID(nil)
        }
        state = .signedOut
    }

    // MARK: Presentation helpers

    /// The state an error interrupted, or the current state when there is no error. This is
    /// what a dismissed message returns to.
    var stableState: State {
        if case let .error(_, previousStable) = state { return previousStable }
        return state
    }

    var isRecoverableError: Bool {
        if case .error = state { return true }
        return false
    }

    var currentProfile: MALUserIdentity? {
        switch stableState {
        case let .signedIn(profile, _, _), let .refreshing(profile):
            return profile
        case let .reauthorizationRequired(profile):
            return profile
        case .signedOut, .authorizing:
            return preferences.load()?.profile
        case .error:
            return nil
        }
    }

    private static let signInFailureMessage =
        "MyAnimeList sign-in could not be completed. Please try again."

    /// `mangareader://oauth/mal` presents to `ASWebAuthenticationSession` as the scheme alone.
    private static func callbackScheme(from redirectURI: String) -> String {
        URLComponents(string: redirectURI)?.scheme ?? redirectURI
    }

    private static let randomBytes: @Sendable (Int) -> Data = { count in
        Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }
}

/// Production preference storage. `UserDefaults` is right here: none of it is secret, and the
/// queued-account marker must survive a sign-out.
final class MALUserDefaultsAccountPreferenceStore: MALAccountPreferenceStore, @unchecked Sendable {
    private enum Key {
        static let account = "mal.account.preferences"
        static let queuedAccount = "mal.account.queuedUserID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MALAccountPreferences? {
        guard let data = defaults.data(forKey: Key.account) else { return nil }
        return try? JSONDecoder().decode(MALAccountPreferences.self, from: data)
    }

    func save(_ preferences: MALAccountPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Key.account)
    }

    func clear() {
        defaults.removeObject(forKey: Key.account)
    }

    func loadQueuedAccountUserID() -> Int? {
        defaults.object(forKey: Key.queuedAccount) as? Int
    }

    func saveQueuedAccountUserID(_ userID: Int?) {
        if let userID {
            defaults.set(userID, forKey: Key.queuedAccount)
        } else {
            defaults.removeObject(forKey: Key.queuedAccount)
        }
    }
}
