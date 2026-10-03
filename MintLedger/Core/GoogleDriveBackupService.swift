import Foundation
import GoogleSignIn
import Observation
import UIKit

struct GoogleDriveBackupFile: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let modifiedAt: Date
    let size: Int64
}

@MainActor
@Observable
final class GoogleDriveBackupService {
    private(set) var isSignedIn = false
    private(set) var accountEmail: String?
    private(set) var isWorking = false
    private(set) var backups: [GoogleDriveBackupFile] = []
    private(set) var lastBackupDate: Date?
    private(set) var lastError: String?

    private var pendingAutomaticBackup: Task<Void, Never>?

    private static let clientID = "303304475122-5epn04u3v0ghe0schfg3g74l11ig0que.apps.googleusercontent.com"
    private static let driveScope = "https://www.googleapis.com/auth/drive.appdata"
    private static let backupPrefix = "MintLedger-Backup-"

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Self.clientID)
    }

    func restorePreviousSignIn() async {
        do {
            let user = try await restoreUser()
            guard user.grantedScopes?.contains(Self.driveScope) == true else {
                GIDSignIn.sharedInstance.signOut()
                clearSession()
                return
            }
            apply(user: user)
            await refreshBackups()
        } catch {
            clearSession()
        }
    }

    func signIn() async {
        guard let presenter = presentingViewController() else {
            lastError = GoogleDriveBackupError.noPresentationContext.localizedDescription
            return
        }

        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let user: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [Self.driveScope]
                ) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let user = result?.user {
                        continuation.resume(returning: user)
                    } else {
                        continuation.resume(throwing: GoogleDriveBackupError.invalidResponse)
                    }
                }
            }
            apply(user: user)
            await refreshBackups()
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    func signOut() {
        pendingAutomaticBackup?.cancel()
        GIDSignIn.sharedInstance.signOut()
        clearSession()
    }

    func scheduleAutomaticBackup(data: Data) {
        guard isSignedIn else { return }
        pendingAutomaticBackup?.cancel()
        pendingAutomaticBackup = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.uploadBackup(data: data, reportsErrors: false)
        }
    }

    func backupNow(data: Data) async {
        pendingAutomaticBackup?.cancel()
        await uploadBackup(data: data, reportsErrors: true)
    }

    func refreshBackups() async {
        guard isSignedIn else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            backups = try await fetchBackups()
            lastBackupDate = backups.first?.modifiedAt
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    func download(_ backup: GoogleDriveBackupFile) async throws -> Data {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            return try await authorizedData(
                url: URL(string: "https://www.googleapis.com/drive/v3/files/\(backup.id)?alt=media")!
            )
        } catch {
            lastError = readableMessage(for: error)
            throw error
        }
    }

    func delete(_ backup: GoogleDriveBackupFile) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(backup.id)")!)
            request.httpMethod = "DELETE"
            _ = try await authorizedData(for: request, acceptsEmptyResponse: true)
            backups.removeAll { $0.id == backup.id }
            lastBackupDate = backups.first?.modifiedAt
        } catch {
            lastError = readableMessage(for: error)
        }
    }

    private func uploadBackup(data: Data, reportsErrors: Bool) async {
        guard isSignedIn else { return }
        isWorking = true
        if reportsErrors { lastError = nil }
        defer { isWorking = false }

        do {
            let name = Self.dailyBackupName()
            let currentBackups = try await fetchBackups()
            if let existing = currentBackups.first(where: { $0.name == name }) {
                var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(existing.id)?uploadType=media")!)
                request.httpMethod = "PATCH"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data
                _ = try await authorizedData(for: request)
            } else {
                try await createBackup(name: name, data: data)
            }

            backups = try await fetchBackups()
            lastBackupDate = backups.first?.modifiedAt
            await pruneOldBackups()
        } catch {
            if reportsErrors { lastError = readableMessage(for: error) }
        }
    }

    private func createBackup(name: String, data: Data) async throws {
        let boundary = "MintLedger-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": ["appDataFolder"],
            "mimeType": "application/json"
        ])

        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8Data)
        body.append(metadata)
        body.append("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".utf8Data)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await authorizedData(for: request)
    }

    private func fetchBackups() async throws -> [GoogleDriveBackupFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime,size)"),
            URLQueryItem(name: "q", value: "'appDataFolder' in parents and trashed = false and name contains '\(Self.backupPrefix)'")
        ]
        let data = try await authorizedData(url: components.url!)
        let response = try JSONDecoder().decode(DriveFileListResponse.self, from: data)
        return response.files.compactMap { file in
            guard let date = Self.internetDate(file.modifiedTime) else { return nil }
            return GoogleDriveBackupFile(
                id: file.id,
                name: file.name,
                modifiedAt: date,
                size: Int64(file.size ?? "0") ?? 0
            )
        }
    }

    private func pruneOldBackups() async {
        guard backups.count > 30 else { return }
        for backup in backups.dropFirst(30) {
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(backup.id)")!)
            request.httpMethod = "DELETE"
            _ = try? await authorizedData(for: request, acceptsEmptyResponse: true)
        }
        backups = Array(backups.prefix(30))
    }

    private func authorizedData(url: URL) async throws -> Data {
        try await authorizedData(for: URLRequest(url: url))
    }

    private func authorizedData(for originalRequest: URLRequest, acceptsEmptyResponse: Bool = false) async throws -> Data {
        let token = try await freshAccessToken()
        var request = originalRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleDriveBackupError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleDriveBackupError.server(detail)
        }
        if data.isEmpty, !acceptsEmptyResponse {
            return Data()
        }
        return data
    }

    private func freshAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleDriveBackupError.notSignedIn
        }
        let refreshedUser: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleDriveBackupError.invalidResponse)
                }
            }
        }
        return refreshedUser.accessToken.tokenString
    }

    private func restoreUser() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleDriveBackupError.notSignedIn)
                }
            }
        }
    }

    private func apply(user: GIDGoogleUser) {
        isSignedIn = true
        accountEmail = user.profile?.email
        lastError = nil
    }

    private func clearSession() {
        isSignedIn = false
        accountEmail = nil
        backups = []
        lastBackupDate = nil
        lastError = nil
    }

    private func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        return presenter
    }

    private func readableMessage(for error: Error) -> String {
        return error.localizedDescription
    }

    private static func dailyBackupName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(backupPrefix)\(formatter.string(from: .now)).mintledger"
    }

    private static func internetDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct DriveFileListResponse: Decodable {
    let files: [DriveFileMetadata]
}

private struct DriveFileMetadata: Decodable {
    let id: String
    let name: String
    let modifiedTime: String
    let size: String?
}

private enum GoogleDriveBackupError: LocalizedError {
    case noPresentationContext
    case notSignedIn
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noPresentationContext: "目前無法顯示 Google 登入畫面，請稍後再試"
        case .notSignedIn: "尚未登入 Google 帳號"
        case .invalidResponse: "Google Drive 回傳了無法辨識的資料"
        case .server(let detail): "Google Drive 備份失敗：\(detail)"
        }
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
