// Films a display until stdin closes, showing only the windows an app makes from then on (its floating panel, the
// welcome, from its first frame) on a gray backdrop, then crops the film to the panel plus 32 pt (its frame when it
// first showed; it may be gone by then; a borderless panel has no title to find it by). H.264 at the display's scale,
// 60 fps. Never a window that was there before (the app's main window neither), another app's, the desktop or the
// pointer; the panel's glass still blurs what is behind it on screen. Needs ffmpeg.
// Usage: record-window <pid> <out.mp4>
import AVFoundation
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: record-window <pid> <out.mp4>\n".utf8))
    exit(2)
}

let out = URL(filePath: arguments[2])
let level = Int(CGWindowLevelForKey(.floatingWindow))
let margin = 32.0
let film = out.deletingPathExtension().appendingPathExtension("full.mp4")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data("\(text)\n".utf8))
    exit(1)
}

final class Finished: NSObject, SCRecordingOutputDelegate {
    let (ended, end) = AsyncStream<Void>.makeStream()
    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        end.finish()
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        end.finish()
    }
}

let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
/// The display of the app's largest window.
let largest = content.windows.filter { $0.owningApplication?.processID == pid }
    .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
guard let display = content.displays.first(where: { $0.frame.intersects(largest?.frame ?? .null) })
    ?? content.displays.first else { fail("no display") }
// The app's windows made from now on (the panel, from its first frame, with no poll's delay) on the backdrop; none of
// the windows already there, nor another app's.
guard let app = content.applications.first(where: { $0.processID == pid }) else { fail("no app with pid \(pid)") }
/// Only its normal windows: a closing menu's window in the list stopped the stream once it closed.
let filter = SCContentFilter(display: display, including: [app], exceptingWindows: content.windows.filter {
    $0.owningApplication?.processID == pid && $0.windowLayer == 0
})
let scale = CGFloat(filter.pointPixelScale)
/// Kept for the run: the configuration does not retain it.
let backdrop = CGColor(gray: 0.5, alpha: 1)
let config = SCStreamConfiguration()
config.width = Int(display.frame.width * scale)
config.height = Int(display.frame.height * scale)
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.captureResolution = .best
config.showsCursor = false
config.backgroundColor = backdrop
final class Stopped: NSObject, SCStreamDelegate {
    func stream(_: SCStream, didStopWithError error: any Error) {
        FileHandle.standardError.write(Data("the stream stopped: \(error)\n".utf8))
    }
}

let stopped = Stopped()
let stream = SCStream(filter: filter, configuration: config, delegate: stopped)
let recording = SCRecordingOutputConfiguration()
recording.outputURL = film
recording.outputFileType = .mp4
recording.videoCodecType = .h264
let finished = Finished()
try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: finished))
/// In an async function, so the async start and stop are the ones called (top-level code took the handler forms).
func capture(_ start: Bool) async throws {
    if start {
        try await stream.startCapture()
    } else {
        try await stream.stopCapture()
    }
}

func shown() async -> SCWindow? {
    let windows = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true).windows
    return windows?.first { $0.owningApplication?.processID == pid && $0.windowLayer == level }
}

try await capture(true)
// The film is for the panel's first frames: it must not be there yet.
if await shown() != nil {
    fail("the panel showed before the recording")
}

print("recording")
fflush(stdout)

/// The panel's frame when it first shows, in the display's points.
nonisolated(unsafe) var frame: CGRect? // set by the poll only, read after it ends
let poll = Task {
    while !Task.isCancelled {
        if let window = await shown() {
            frame = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            return
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
}

// Never filming on after the app: a test that quit it without a stop.
Task.detached {
    while kill(pid, 0) == 0 {
        try? await Task.sleep(for: .seconds(2))
    }
    fail("the app (pid \(pid)) quit while filming")
}

// Off the main actor, which the poll needs.
await Task.detached { while readLine() != nil {} }.value
poll.cancel()
_ = await poll.value
try await capture(false)
for await _ in finished.ended {}
guard let frame else { fail("no floating panel of pid \(pid) showed; the full film is \(film.path)") }
let rect = frame.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: display.frame.size))
// Even pixel sizes: H.264 needs them.
let crop = [rect.width, rect.height, rect.minX, rect.minY].map { Int($0 * scale) / 2 * 2 }
let cropping = "crop=\(crop[0]):\(crop[1]):\(crop[2]):\(crop[3])"

/// Runs ffmpeg; what it printed on stderr.
func ffmpeg(_ arguments: [String]) throws -> String {
    let run = Process(), errors = Pipe()
    run.executableURL = URL(filePath: "/usr/bin/env")
    run.environment = ["PATH": "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
    run.arguments = ["ffmpeg", "-y"] + arguments
    run.standardError = errors
    try run.run()
    let printed = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    run.waitUntilExit()
    guard run.terminationStatus == 0 else { fail("ffmpeg failed; the full film is \(film.path)\n\(printed)") }
    return printed
}

/// The film starts at its first drawn frame, the panel's, unless the backdrop was drawn first: then the cut is 0.3 s
/// before the backdrop's still ends.
let first = { (text: String, name: String) in
    (try? Regex("\(name)[:=] ?([0-9.]+)")).flatMap { text.firstMatch(of: $0) }
        .flatMap { Double($0.output[1].substring ?? "") }
}

let opening = try ffmpeg(["-i", film.path, "-frames:v", "1", "-vf", "\(cropping),signalstats,metadata=print", "-f",
                          "null", "-"])
let blank = (first(opening, "YMAX") ?? 255) - (first(opening, "YMIN") ?? 0) < 4
let still = blank ? try ffmpeg(["-i", film.path, "-vf", "\(cropping),freezedetect=n=0.001:d=0.1", "-an", "-f",
                                "null", "-"]) : ""
let end = first(still, "freeze_end") ?? 0
_ = try ffmpeg(["-loglevel", "error", "-ss", "\(max(0, end - 0.3))", "-i", film.path, "-vf", cropping, "-c:v",
                "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                out.path])
try? FileManager.default.removeItem(at: film)
