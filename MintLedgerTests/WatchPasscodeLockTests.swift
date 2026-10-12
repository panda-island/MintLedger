import XCTest
@testable import MintLedger

@MainActor
final class WatchPasscodeLockTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var storage: MemoryPasscodeStorage!

    override func setUp() async throws {
        suiteName = "MintLedgerTests.WatchLock.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        storage = MemoryPasscodeStorage()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testEnableRelaunchAndUnlockRequireCorrectPIN() throws {
        let lock = WatchPasscodeLockService(storage: storage, defaults: defaults)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertThrowsError(try lock.enable(pin: "12a4"))
        XCTAssertThrowsError(try lock.enable(pin: "１２３４"))
        try lock.enable(pin: "0123")
        XCTAssertTrue(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)

        let relaunched = WatchPasscodeLockService(storage: storage, defaults: defaults)
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertThrowsError(try relaunched.unlock(pin: "9999"))
        XCTAssertTrue(relaunched.isLocked)
        try relaunched.unlock(pin: "0123")
        XCTAssertFalse(relaunched.isLocked)
        relaunched.lock()
        XCTAssertTrue(relaunched.isLocked)
    }

    func testChangeAndDisableRequireCurrentPIN() throws {
        let lock = WatchPasscodeLockService(storage: storage, defaults: defaults)
        try lock.enable(pin: "1234")
        XCTAssertThrowsError(try lock.enable(pin: "9999"))
        XCTAssertThrowsError(try lock.changePIN(currentPIN: "9999", newPIN: "5678"))
        XCTAssertThrowsError(try lock.disable(currentPIN: "9999"))
        XCTAssertTrue(lock.isEnabled)
        try lock.changePIN(currentPIN: "1234", newPIN: "5678")
        lock.lock()
        XCTAssertThrowsError(try lock.unlock(pin: "1234"))
        try lock.unlock(pin: "5678")
        try lock.disable(currentPIN: "5678")
        XCTAssertFalse(lock.isEnabled)
        XCTAssertNil(storage.data)
        XCTAssertFalse(WatchPasscodeLockService(storage: storage, defaults: defaults).isEnabled)
    }

    func testRateLimitSurvivesRelaunchAndExpires() throws {
        var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
        let lock = WatchPasscodeLockService(storage: storage, defaults: defaults, now: { currentTime })
        try lock.enable(pin: "1234")
        lock.lock()
        for _ in 0..<5 { XCTAssertThrowsError(try lock.unlock(pin: "9999")) }
        let relaunched = WatchPasscodeLockService(storage: storage, defaults: defaults, now: { currentTime })
        XCTAssertThrowsError(try relaunched.unlock(pin: "1234"))
        XCTAssertTrue(relaunched.isLocked)
        currentTime = currentTime.addingTimeInterval(61)
        try relaunched.unlock(pin: "1234")
        XCTAssertFalse(relaunched.isLocked)
        XCTAssertNil(relaunched.retryAfter)
    }

    func testStorageFailuresDoNotEnableOrRemoveProtection() throws {
        let lock = WatchPasscodeLockService(storage: storage, defaults: defaults)
        storage.fails = true
        XCTAssertThrowsError(try lock.enable(pin: "1234"))
        XCTAssertFalse(lock.isEnabled)
        storage.fails = false
        try lock.enable(pin: "1234")
        lock.lock()
        storage.fails = true
        XCTAssertThrowsError(try lock.unlock(pin: "1234"))
        XCTAssertThrowsError(try lock.disable(currentPIN: "1234"))
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.isEnabled)
    }

    func testCredentialRestoresProtectionWithoutPreferenceAndEarlyStorageErrorRecovers() throws {
        storage.data = Data("1234".utf8)
        let lock = WatchPasscodeLockService(storage: storage, defaults: defaults)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.isEnabled)

        storage.data = nil
        storage.fails = true
        let earlyLaunch = WatchPasscodeLockService(storage: storage, defaults: defaults)
        XCTAssertTrue(earlyLaunch.isLocked)
        storage.fails = false
        earlyLaunch.refreshConfiguration()
        XCTAssertFalse(earlyLaunch.isEnabled)
        XCTAssertFalse(earlyLaunch.isLocked)
    }

    func testMigratedPreferencesWithoutDeviceOnlyCredentialDoNotLockOutNewWatch() {
        defaults.set(true, forKey: WatchPasscodeLockService.enabledKey)
        let newWatch = WatchPasscodeLockService(storage: storage, defaults: defaults)
        XCTAssertFalse(newWatch.isEnabled)
        XCTAssertFalse(newWatch.isLocked)
    }
}

private final class MemoryPasscodeStorage: WatchPasscodeStorage {
    var data: Data?
    var fails = false
    func read() throws -> Data? {
        if fails { throw WatchPasscodeError.storageUnavailable }
        return data
    }
    func save(_ data: Data) throws {
        if fails { throw WatchPasscodeError.storageUnavailable }
        self.data = data
    }
    func delete() throws {
        if fails { throw WatchPasscodeError.storageUnavailable }
        data = nil
    }
}
