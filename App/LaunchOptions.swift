import Foundation

struct LaunchOptions {
    var isUITesting = false
    var seedSampleData = false
    var keepDrafts = false
    var localeOverride: String?
    var appearanceOverride: String?
    var todayOverride: String?
    /// UI tests only (with `--ui-testing`): the stand-in scanner that returns `SampleReceipt`.
    var fakeScanner = false

    static func parse(_ args: [String] = CommandLine.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--ui-testing": options.isUITesting = true
            case "--seed-sample-data": options.seedSampleData = true
            case "--keep-drafts": options.keepDrafts = true
            case "--locale": options.localeOverride = iterator.next()
            case "--appearance": options.appearanceOverride = iterator.next()
            case "--today": options.todayOverride = iterator.next()
            case "--fake-scanner": options.fakeScanner = true
            default: break
            }
        }
        return options
    }
}
