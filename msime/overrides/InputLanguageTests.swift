import XCTest

/// 「输入」页的语言行：定制版只保留全拼与手写，其余方案没有任何一行能显示或启用它。
final class InputLanguageTests: XCTestCase {
  func testOnlyQuanpinAndHandwritingRowsExist() {
    XCTAssertEqual(InputLanguage.allCases, [.quanpin, .handwriting])
    XCTAssertEqual(InputLanguage.quanpin.name, "全拼")
    XCTAssertEqual(InputLanguage.handwriting.name, "手写")
    XCTAssertEqual(InputLanguage.quanpin.schemes, [.quanpin])
    XCTAssertEqual(InputLanguage.handwriting.schemes, [.handwriting])
  }

  func testEachOfferedSchemeBelongsToExactlyOneLanguage() {
    for scheme in ChineseInputScheme.allCases.filter(\.isOfferedByEdition) {
      let owners = InputLanguage.allCases.filter { $0.schemes.contains(scheme) }
      XCTAssertEqual(owners.count, 1, "\(scheme) belongs to \(owners)")
    }
  }

  func testRemovedSchemesHaveNoLanguageRow() {
    for scheme in ChineseInputScheme.allCases where !scheme.isOfferedByEdition {
      XCTAssertTrue(InputLanguage.allCases.allSatisfy { !$0.schemes.contains(scheme) },
                    "removed scheme \(scheme) still has a language row")
    }
  }
}
