import Foundation

struct LaunchOptions {
    var isUITesting = false
    var seedSampleData = false
    var localeOverride: String?
    var appearanceOverride: String?

    static func parse(_ args: [String] = CommandLine.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--ui-testing": options.isUITesting = true
            case "--seed-sample-data": options.seedSampleData = true
            case "--locale": options.localeOverride = iterator.next()
            case "--appearance": options.appearanceOverride = iterator.next()
            default: break
            }
        }
        return options
    }
}
