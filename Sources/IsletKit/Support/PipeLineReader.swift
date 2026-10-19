import Foundation

/// 逐行讀取 pipe：readabilityHandler 在背景佇列收資料、切成行，再依序交給主執行緒。
///
/// 不用 `FileHandle.bytes.lines`：Foundation 的 AsyncBytes 共用同一個 IO actor，
/// 同時讀 stdout 與 stderr 時，沒有資料的那個 pipe 會卡住另一個（大的封面資料就讀不完）。
nonisolated final class PipeLineReader: @unchecked Sendable {
    private let handle: FileHandle
    /// 只在 readabilityHandler 的序列佇列上存取。
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    /// `onLine` 每收到一行呼叫一次；pipe 關閉（程式結束）時呼叫 `onEnd`。
    func start(onLine: @escaping @MainActor (String) -> Void, onEnd: @escaping @MainActor () -> Void) {
        handle.readabilityHandler = { [self] fileHandle in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
                let rest = buffer
                buffer.removeAll()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if !rest.isEmpty, let line = String(data: rest, encoding: .utf8) {
                            onLine(line)
                        }
                        onEnd()
                    }
                }
                return
            }

            let searchStart = buffer.endIndex
            buffer.append(chunk)
            guard buffer[searchStart...].contains(0x0A) else { return }

            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                if let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8) {
                    lines.append(line)
                }
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    lines.forEach(onLine)
                }
            }
        }
    }

    func stop() {
        handle.readabilityHandler = nil
    }
}
