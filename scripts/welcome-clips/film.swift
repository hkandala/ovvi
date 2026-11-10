// Films the display of an app's largest window until stdin closes: only that app's windows (ScreenCaptureKit), never
// another app's, the desktop or the pointer; H.264 at the display's scale, 60 fps. welcome-clips.sh crops it.
// Usage: film <pid> <out.mp4>
import AVFoundation
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: film <pid> <out.mp4>\n".utf8))
    exit(2)
}

final class Finished: NSObject, SCRecordingOutputDelegate {
    let done = DispatchSemaphore(value: 0)
    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        done.signal()
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        done.signal()
    }
}

var content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
// A launching app: its first window comes within a few seconds.
for _ in 0 ..< 50 where !content.windows.contains(where: { $0.owningApplication?.processID == pid }) {
    try await Task.sleep(for: .milliseconds(200))
    content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

guard let app = content.applications.first(where: { $0.processID == pid }),
      let largest = content.windows.filter({ $0.owningApplication?.processID == pid })
          .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
      let display = content.displays.first(where: { $0.frame.intersects(largest.frame) })
else {
    FileHandle.standardError.write(Data("no window of pid \(pid)\n".utf8))
    exit(1)
}

let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
let config = SCStreamConfiguration()
config.width = Int(display.frame.width * CGFloat(filter.pointPixelScale))
config.height = Int(display.frame.height * CGFloat(filter.pointPixelScale))
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.captureResolution = .best
config.showsCursor = false
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
let recording = SCRecordingOutputConfiguration()
recording.outputURL = URL(filePath: arguments[2])
recording.outputFileType = .mp4
recording.videoCodecType = .h264
let finished = Finished()
try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: finished))
try await stream.startCapture()
print("recording")
fflush(stdout)
while readLine() != nil {}
try await stream.stopCapture()
finished.done.wait()
