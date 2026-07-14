import Foundation

/// A tiny, dependency-free test harness.
///
/// Picotime is a deliberately no-Xcode project, and `swift test`'s runner needs
/// Xcode's `xctest` tool — so tests run as a plain SPM executable using this
/// instead of XCTest/swift-testing. Failing checks print to stderr and the
/// process exits non-zero, so build.sh and CI can gate on the result.
final class TestRunner {
    private var checks = 0
    private var failures = 0
    private var current = ""

    /// Group a set of expectations under a named test (for readable failures).
    func test(_ name: String, _ body: () -> Void) {
        current = name
        body()
    }

    /// Assert `condition` is true; record and report a failure otherwise.
    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "",
                file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        guard !condition else { return }
        failures += 1
        let detail = message()
        let suffix = detail.isEmpty ? "" : " — \(detail)"
        FileHandle.standardError.write(Data("✗ [\(current)] \(file):\(line)\(suffix)\n".utf8))
    }

    /// Assert `actual == expected`, reporting both values on mismatch.
    func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                                   file: StaticString = #fileID, line: UInt = #line) {
        expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
    }

    /// Print a summary and exit (0 = all passed, 1 = at least one failure).
    func summarize() -> Never {
        if failures == 0 {
            print("✓ all \(checks) checks passed")
            exit(0)
        }
        print("✗ \(failures) of \(checks) checks failed")
        exit(1)
    }
}
