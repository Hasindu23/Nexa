import XCTest
import Darwin
@testable import Nexa

final class MemoryTests: XCTestCase {
    func app(pid: pid_t = 2_000_000, id: String? = "app.fixture.memory", path: String? = "/Applications/Fixture.app",
             launch: Date? = Date(timeIntervalSince1970: 100), regular: Bool = true, owned: Bool = true) -> MemoryApp {
        MemoryApp(pid: pid, name: "Fixture", bundleID: id, bundlePath: path, launched: launch, regular: regular, owned: owned, bytes: 42)
    }
    func testQuitRequiresConfirmationBeforeAnyRequest() {
        var sent = false
        XCTAssertThrowsError(try MemoryQuitGate.request(app(), confirmed: false, current: app()) { sent = true; return true })
        XCTAssertFalse(sent)
    }
    func testQuitRejectsSystemBackgroundForeignAndUnidentifiedApps() {
        for target in [app(pid: getpid()), app(pid: 1), app(id: "com.apple.finder"), app(id: "app.nexa.mac"),
                       app(regular: false), app(owned: false), app(id: nil), app(path: nil), app(launch: nil)] {
            var sent = false
            XCTAssertThrowsError(try MemoryQuitGate.request(target, confirmed: true, current: target) { sent = true; return true })
            XCTAssertFalse(sent)
        }
    }
    func testPidReuseAndChangedIdentityNeverQuitAnotherApp() {
        for current in [app(launch: Date(timeIntervalSince1970: 200)), app(id: "app.changed"), app(path: "/Applications/Other.app"), app(pid: 2_000_001), app(owned: false)] {
            var sent = false
            XCTAssertThrowsError(try MemoryQuitGate.request(app(), confirmed: true, current: current) { sent = true; return true })
            XCTAssertFalse(sent)
        }
    }
    func testVanishedAppCannotBeQuit() {
        XCTAssertThrowsError(try MemoryQuitGate.request(app(), confirmed: true, current: nil) { XCTFail("Must not send a request"); return true })
    }
    func testConfirmedQuitUsesOnlyOneNormalRequestAndReportsRefusal() throws {
        var calls = 0
        try MemoryQuitGate.request(app(), confirmed: true, current: app()) { calls += 1; return true }
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try MemoryQuitGate.request(app(), confirmed: true, current: app()) { calls += 1; return false })
        XCTAssertEqual(calls, 2)
    }
    func testLiveMemoryReadHasPlausibleValuesAndSelfFootprint() throws {
        let sample = try MemorySnapshot.read()
        XCTAssertEqual(sample.total, ProcessInfo.processInfo.physicalMemory)
        XCTAssertLessThanOrEqual(sample.free, sample.total)
        XCTAssertGreaterThan(try XCTUnwrap(MemorySnapshot.footprint(pid: getpid())), 0)
        XCTAssertNil(MemorySnapshot.footprint(pid: -1))
    }
    func testUnknownPressureIsNotReportedAsHealthyOrCritical() {
        let sample = MemorySnapshot(date: Date(), total: 100, free: 10, wired: 10, compressed: 10, swap: nil, pressure: 900)
        XCTAssertEqual(sample.pressureName, "Unavailable")
    }
}
