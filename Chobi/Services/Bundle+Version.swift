import Foundation

extension Bundle {
    /// Returns the application version string.
    /// If the version is the default Xcode local fallback ("1.0"), it dynamically constructs
    /// a date-based development version (e.g., "26.05.28-dev") to align with the CI/CD scheme.
    public var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        if version == "1.0" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yy.MM.dd"
            let dateStr = formatter.string(from: Date())
            return "\(dateStr)-dev"
        }
        return version
    }

    /// Returns the application build/project version string.
    /// If the build number is the default local fallback ("1"), it dynamically constructs
    /// a timestamp-based build number (e.g., "2605281940") to match the CI/CD build number format.
    public var appBuildNumber: String {
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        if build == "1" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyMMddHHmm"
            return formatter.string(from: Date())
        }
        return build
    }
}
