import Foundation
import Observation
import Security

protocol WatchPasscodeStorage {
    func read() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

struct WatchPasscodeKeychain: WatchPasscodeStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.pandaisland.mintledger.watch.passcode",
         kSecAttrAccount as String: "app-lock",
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WatchPasscodeError.storageUnavailable
        }
        return data
    }

    func save(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw WatchPasscodeError.storageUnavailable
            }
        } else if status != errSecSuccess {
            throw WatchPasscodeError.storageUnavailable
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WatchPasscodeError.storageUnavailable
        }
    }
}

enum WatchPasscodeError: LocalizedError {
    case invalidPIN, incorrectPIN, storageUnavailable, alreadyEnabled, notEnabled
    case rateLimited(Date)

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "請輸入 4 位數字密碼。"
        case .incorrectPIN: return "密碼錯誤，請再試一次。"
        case .storageUnavailable: return "無法讀取安全儲存區，請先解鎖 Apple Watch 後再試。"
        case .alreadyEnabled: return "密碼鎖已啟用，請使用更改密碼。"
        case .notEnabled: return "尚未啟用密碼鎖。"
        case .rateLimited: return "錯誤次數過多，請稍後再試。"
        }
    }
}

@MainActor
@Observable
final class WatchPasscodeLockService {
    static let enabledKey = "mintledger.watch.passcode.enabled"
    private static let attemptsKey = "mintledger.watch.passcode.attempts"
    private static let retryKey = "mintledger.watch.passcode.retry-after"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var retryAfter: Date?

    @ObservationIgnored private let storage: any WatchPasscodeStorage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(
        storage: any WatchPasscodeStorage = WatchPasscodeKeychain(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.storage = storage
        self.defaults = defaults
        self.now = now
        // A saved credential also restores the lock if preferences were reset.
        // Any Keychain error fails closed instead of revealing cached accounts.
        let enabled: Bool
        do {
            enabled = try storage.read() != nil || defaults.bool(forKey: Self.enabledKey)
        } catch {
            enabled = true
        }
        isEnabled = enabled
        isLocked = enabled
        retryAfter = defaults.object(forKey: Self.retryKey) as? Date
    }

    static func isValidPIN(_ pin: String) -> Bool {
        pin.utf8.count == 4 && pin.utf8.allSatisfy { (48...57).contains($0) }
    }

    func enable(pin: String) throws {
        guard !isEnabled else { throw WatchPasscodeError.alreadyEnabled }
        guard Self.isValidPIN(pin) else { throw WatchPasscodeError.invalidPIN }
        try storage.save(Data(pin.utf8))
        defaults.set(true, forKey: Self.enabledKey)
        isEnabled = true
        isLocked = false
        resetAttempts()
    }

    func lock() {
        if isEnabled { isLocked = true }
    }

    func refreshConfiguration() {
        // Background launches can occur before the system Keychain is accessible.
        // Retry once active, while retaining protection on storage errors.
        do {
            let enabled = try storage.read() != nil || defaults.bool(forKey: Self.enabledKey)
            if enabled && !isEnabled { isLocked = true }
            if !enabled { isLocked = false }
            isEnabled = enabled
        } catch {
            isEnabled = true
            isLocked = true
        }
    }

    func unlock(pin: String) throws {
        try verify(pin: pin)
        isLocked = false
    }

    func verify(pin: String) throws {
        guard isEnabled else { throw WatchPasscodeError.notEnabled }
        if let retryAfter, retryAfter > now() {
            throw WatchPasscodeError.rateLimited(retryAfter)
        }
        guard Self.isValidPIN(pin) else { throw WatchPasscodeError.invalidPIN }
        guard let saved = try storage.read(), saved.count == 4 else {
            throw WatchPasscodeError.storageUnavailable
        }
        let input = Data(pin.utf8)
        let difference = zip(saved, input).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else {
            let attempts = defaults.integer(forKey: Self.attemptsKey) + 1
            if attempts >= 5 {
                let deadline = now().addingTimeInterval(60)
                retryAfter = deadline
                defaults.set(deadline, forKey: Self.retryKey)
                defaults.set(0, forKey: Self.attemptsKey)
                throw WatchPasscodeError.rateLimited(deadline)
            }
            defaults.set(attempts, forKey: Self.attemptsKey)
            throw WatchPasscodeError.incorrectPIN
        }
        resetAttempts()
    }

    func changePIN(currentPIN: String, newPIN: String) throws {
        guard Self.isValidPIN(newPIN) else { throw WatchPasscodeError.invalidPIN }
        try verify(pin: currentPIN)
        try storage.save(Data(newPIN.utf8))
    }

    func disable(currentPIN: String) throws {
        try verify(pin: currentPIN)
        try storage.delete()
        defaults.set(false, forKey: Self.enabledKey)
        isEnabled = false
        isLocked = false
    }

    private func resetAttempts() {
        defaults.removeObject(forKey: Self.attemptsKey)
        defaults.removeObject(forKey: Self.retryKey)
        retryAfter = nil
    }
}
