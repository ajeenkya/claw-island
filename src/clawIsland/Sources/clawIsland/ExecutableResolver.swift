import Foundation

/// Resolves executable paths across common macOS/Homebrew installations.
enum ExecutableResolver {
    static func resolve(executable name: String, preferredPaths: [String] = []) -> String? {
        let fileManager = FileManager.default
        
        for path in preferredPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        
        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathValue.split(separator: ":") {
                let candidate = String(directory) + "/\(name)"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        
        let fallbackPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for base in fallbackPaths {
            let candidate = "\(base)/\(name)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        
        return nil
    }
}
