import Foundation

enum ProcessRunner {
    /// 執行外部程式並收集完整 stdout；失敗或 exit code 不是 0 時回傳 nil。
    /// 在背景佇列上邊讀邊等，輸出比 pipe 緩衝區大也不會卡住。
    static func output(_ executable: URL, arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
        }
    }

    /// 執行外部程式直到結束，回傳 exit code；啟動失敗、被訊號中止或逾時回傳 nil。
    static func run(_ executable: URL, arguments: [String], timeout: Duration) async -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }
        defer { timeoutTask.cancel() }

        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationReason == .exit ? finished.terminationStatus : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
        // 確保 Process 物件活到結束通知送達之後
        return withExtendedLifetime(process) { status }
    }
}
