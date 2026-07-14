// Test entry point: run every suite against a shared TestRunner, then exit with
// a status that reflects pass/fail. Run via ./run-tests.sh (or `swift run
// PicotimeCoreTests`); ./coverage.sh runs it instrumented and reports coverage.

let runner = TestRunner()

clockFormatTests(runner)
hourChimeTests(runner)
calendarGridTests(runner)

runner.summarize()
