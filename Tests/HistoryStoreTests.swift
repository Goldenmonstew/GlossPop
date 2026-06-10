import XCTest
@testable import GlossPop

@MainActor
final class HistoryStoreTests: XCTestCase {
    override func setUp() { HistoryStore.clear() }
    override func tearDown() { HistoryStore.clear(); HistoryStore.isEnabled = false }

    func testRecordDedupAndFloat() {
        HistoryStore.isEnabled = true
        HistoryStore.record(source: "hello", result: "你好", subtitle: "x")
        HistoryStore.record(source: "world", result: "世界", subtitle: "x")
        HistoryStore.record(source: "hello", result: "你好 v2", subtitle: "x") // same source → float + update
        let all = HistoryStore.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.source, "hello")
        XCTAssertEqual(all.first?.result, "你好 v2")
    }

    func testDisabledDoesNotRecord() {
        HistoryStore.isEnabled = false
        HistoryStore.record(source: "x", result: "y", subtitle: "z")
        XCTAssertTrue(HistoryStore.all().isEmpty)
    }

    func testEmptyResultIgnored() {
        HistoryStore.isEnabled = true
        HistoryStore.record(source: "x", result: "   ", subtitle: "z")
        XCTAssertTrue(HistoryStore.all().isEmpty)
    }
}
