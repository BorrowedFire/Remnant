import OSLog

enum AppLogger {
    static let general = Logger(subsystem: "com.borrowedfire.remnant", category: "general")
    static let data = Logger(subsystem: "com.borrowedfire.remnant", category: "data")
    static let payments = Logger(subsystem: "com.borrowedfire.remnant", category: "payments")
    static let sync = Logger(subsystem: "com.borrowedfire.remnant", category: "sync")
}
