import Foundation

/// 应用内运行日志：记网络请求、缓存命中、本地计算回退、登录等关键事件。
/// 存到 App 沙盒的 paiban-app.log（纯文本，一行一条，最多保留 7 天），
/// 反馈时把最近 24 小时的日志一起发到 NAS，方便定位问题。
/// 线程安全：所有读写走一条串行队列。
final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "paiban.applogger")
    private var entries: [String] = []
    private let maxEntries = 1000
    private let keepDays = 7

    private var logURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("paiban-app.log")
    }

    private init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        queue.sync {
            guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
            var lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            lines = prune(lines)
            entries = Array(lines.suffix(maxEntries))
        }
    }

    /// 删掉超过 keepDays 的旧行（按行首的 ISO 时间判断，解析不出的行保留）。
    private func prune(_ lines: [String]) -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        let formatter = ISO8601DateFormatter()
        return lines.filter { line in
            guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return true }
            let stamp = String(line[line.index(after: line.startIndex)..<end])
            guard let date = formatter.date(from: stamp) else { return true }
            return date >= cutoff
        }
    }

    /// 记一条日志。tag 如 API / Cache / Pay / Auth。
    func log(_ message: String, tag: String = "App") {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] [\(tag)] \(message)"
        queue.async {
            self.entries.append(line)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            // 追加写盘；失败就忽略（日志不能影响正常功能）。
            if let data = (line + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logURL, options: .atomic)
                }
            }
        }
    }

    /// 最近 hours 小时内的日志（纯文本，一行一条）。没有日志时返回一行说明。
    func recentLogs(hours: Int = 24) -> String {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let formatter = ISO8601DateFormatter()
        return queue.sync {
            let recent = entries.filter { line in
                guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return true }
                let stamp = String(line[line.index(after: line.startIndex)..<end])
                guard let date = formatter.date(from: stamp) else { return true }
                return date >= cutoff
            }
            if recent.isEmpty { return "（最近 \(hours) 小时没有运行日志）" }
            return recent.joined(separator: "\n")
        }
    }
}
