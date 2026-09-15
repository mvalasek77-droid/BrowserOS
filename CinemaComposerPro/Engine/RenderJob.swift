import Foundation

/// One shot the orchestra actually has to generate.
///
/// A PlanTask is a *budgeting* unit — "all the hero coverage", 1,776 seconds of
/// it. No vendor accepts that as one request. A RenderTarget is the execution
/// unit: one shot, one prompt, one clip that comes back.
struct RenderTarget: Codable, Equatable, Identifiable {
    var id: String
    var seconds: Double
    var prompt: String
    /// Which take this is, when a shot is generated more than once.
    var take: Int = 1

    /// Split a shot the vendor cannot generate in one piece.
    ///
    /// A ten-second ceiling and a fourteen-second shot means two segments, and
    /// the editor conforms them back to back. Returning `[self]` when the shot
    /// already fits keeps the common case free of noise.
    func segments(maxSeconds: Double?) -> [RenderTarget] {
        guard let maxSeconds, maxSeconds > 0, seconds > maxSeconds else { return [self] }
        let count = Int((seconds / maxSeconds).rounded(.up))
        guard count > 1 else { return [self] }
        let each = seconds / Double(count)
        return (0..<count).map { index in
            RenderTarget(id: "\(id)#\(index + 1)",
                         seconds: (each * 100).rounded() / 100,
                         prompt: prompt,
                         take: take)
        }
    }
}

/// How a vendor reports on work that does not finish inside one request.
///
/// Every video generator worth calling is asynchronous: the POST returns a job
/// id, you poll until it is done, then fetch the file. A tool pack that omits
/// this is treated as synchronous — correct for text-to-speech APIs that hand
/// back audio bytes in the response.
struct JobProtocol: Codable, Equatable {
    /// Where to ask about the job. `{{jobId}}` is filled from the submit reply.
    var statusEndpoint: String
    var statusMethod: String = "GET"

    /// Dot path into the submit response that holds the job id, e.g. `"id"`.
    var jobIDPath: String = "id"
    /// Dot path into the status response that holds the state, e.g. `"status"`.
    var statusPath: String = "status"
    /// Dot path to the finished file, e.g. `"output.0"` or `"assets.video"`.
    var resultURLPath: String = "output.0"
    /// Optional dot path to a vendor's failure message, for a useful error.
    var failureMessagePath: String?

    /// State values that end the poll. Compared case-insensitively.
    var succeededValues: [String] = ["succeeded", "success", "completed", "complete", "done"]
    var failedValues: [String] = ["failed", "error", "cancelled", "canceled"]

    var pollSeconds: Double = 5
    var timeoutSeconds: Double = 900

    enum CodingKeys: String, CodingKey {
        case statusEndpoint, statusMethod, jobIDPath, statusPath, resultURLPath
        case failureMessagePath, succeededValues, failedValues, pollSeconds, timeoutSeconds
    }

    init(statusEndpoint: String,
         statusMethod: String = "GET",
         jobIDPath: String = "id",
         statusPath: String = "status",
         resultURLPath: String = "output.0",
         failureMessagePath: String? = nil,
         succeededValues: [String] = ["succeeded", "success", "completed", "complete", "done"],
         failedValues: [String] = ["failed", "error", "cancelled", "canceled"],
         pollSeconds: Double = 5,
         timeoutSeconds: Double = 900) {
        self.statusEndpoint = statusEndpoint
        self.statusMethod = statusMethod
        self.jobIDPath = jobIDPath
        self.statusPath = statusPath
        self.resultURLPath = resultURLPath
        self.failureMessagePath = failureMessagePath
        self.succeededValues = succeededValues
        self.failedValues = failedValues
        self.pollSeconds = pollSeconds
        self.timeoutSeconds = timeoutSeconds
    }

    /// Every field but the status endpoint has a sensible default, so a pack
    /// only has to say what its vendor does differently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusEndpoint = try c.decode(String.self, forKey: .statusEndpoint)
        statusMethod = try c.decodeIfPresent(String.self, forKey: .statusMethod) ?? "GET"
        jobIDPath = try c.decodeIfPresent(String.self, forKey: .jobIDPath) ?? "id"
        statusPath = try c.decodeIfPresent(String.self, forKey: .statusPath) ?? "status"
        resultURLPath = try c.decodeIfPresent(String.self, forKey: .resultURLPath) ?? "output.0"
        failureMessagePath = try c.decodeIfPresent(String.self, forKey: .failureMessagePath)
        succeededValues = try c.decodeIfPresent([String].self, forKey: .succeededValues)
            ?? ["succeeded", "success", "completed", "complete", "done"]
        failedValues = try c.decodeIfPresent([String].self, forKey: .failedValues)
            ?? ["failed", "error", "cancelled", "canceled"]
        pollSeconds = try c.decodeIfPresent(Double.self, forKey: .pollSeconds) ?? 5
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 900
    }

    func isSucceeded(_ state: String) -> Bool {
        succeededValues.contains { $0.compare(state, options: .caseInsensitive) == .orderedSame }
    }

    func isFailed(_ state: String) -> Bool {
        failedValues.contains { $0.compare(state, options: .caseInsensitive) == .orderedSame }
    }
}

/// Reads a value out of a decoded JSON tree by dot path.
///
/// Vendors bury the thing you need at a different depth each time — Runway puts
/// the file at `output.0`, Luma at `assets.video`, Kling at
/// `data.task_result.videos.0.url`. A path in the pack beats a special case in
/// the code for every vendor.
enum JSONPath {

    static func value(_ path: String, in root: Any) -> Any? {
        guard !path.isEmpty else { return root }
        var current: Any? = root
        for component in path.split(separator: ".") {
            guard let node = current else { return nil }
            if let index = Int(component) {
                guard let array = node as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            } else {
                guard let object = node as? [String: Any] else { return nil }
                current = object[String(component)]
            }
        }
        return current
    }

    /// The same lookup, coerced to a string — vendors return ids as both
    /// strings and numbers, and a status as either a string or a bare bool.
    static func string(_ path: String, in root: Any) -> String? {
        guard let node = value(path, in: root) else { return nil }
        // JSONSerialization bridges true/false to NSNumber, so the boolean
        // must be picked out by type before the generic number case —
        // otherwise a status bool stringifies as "1" instead of "true".
        if let number = node as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        switch node {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

/// What one finished generation produced.
struct RenderOutput: Equatable, Sendable {
    var targetID: String
    var remoteURL: URL?
    /// Where the file landed on this device once downloaded.
    var localURL: URL?
    var bytes: Int
    var simulated: Bool
}
