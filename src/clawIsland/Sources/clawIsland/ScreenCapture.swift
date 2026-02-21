import Foundation

/// Captures a screenshot of the frontmost window
class ScreenCapture {
    static let outputPath = "/tmp/milo-screenshot.png"

    /// Capture the active window screenshot. Returns the path on success.
    static func captureActiveWindow() async -> String? {
        do {
            // Get the window ID of the frontmost window
            let idProcess = Process()
            idProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            idProcess.arguments = [
                "-e",
                "tell app \"System Events\" to get id of first window of (first process whose frontmost is true)"
            ]
            let idPipe = Pipe()
            idProcess.standardOutput = idPipe
            idProcess.standardError = Pipe()
            try idProcess.run()
            idProcess.waitUntilExit()

            let idData = idPipe.fileHandleForReading.readDataToEndOfFile()
            let windowId = String(data: idData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !windowId.isEmpty else {
                // Fallback: capture entire screen
                return await captureFullScreen()
            }

            // Capture the specific window
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l\(windowId)", outputPath]
            try process.run()
            process.waitUntilExit()

            return process.terminationStatus == 0 ? outputPath : await captureFullScreen()
        } catch {
            miloLog("⚠️ Screenshot error: \(error)")
            return await captureFullScreen()
        }
    }

    /// Fallback: capture the full screen
    private static func captureFullScreen() async -> String? {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", outputPath]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? outputPath : nil
        } catch {
            return nil
        }
    }
}
