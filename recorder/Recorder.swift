// Records only the Luanti game window, never the display, as 10-minute H.264 segments.
//
//   swiftc -O Recorder.swift -o jevcraft-recorder
//   ./jevcraft-recorder <out-dir>
//
// Frames are written only while <out-dir>/../state/recording exists (the agent creates it while
// Jev is playing), and never while <out-dir> holds more than MAX_BACKLOG bytes of segments that
// have not been uploaded yet. A finished segment is renamed from .part to .mp4 for the uploader.

import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

let SEGMENT_SECONDS = 600.0
let WIDTH = 1280, HEIGHT = 720, FPS: Int32 = 30, BITRATE = 1_200_000
let MAX_BACKLOG: UInt64 = 3 * 1024 * 1024 * 1024

_ = NSApplication.shared // a CLI must set up its window-server connection before ScreenCaptureKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "segments")
let flag = outDir.deletingLastPathComponent().appendingPathComponent("state/recording")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func log(_ s: String) { print("[recorder \(ISO8601DateFormatter().string(from: Date()))] \(s)"); fflush(stdout) }

func backlogBytes() -> UInt64 {
  let files = (try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
  return files.reduce(0) { $0 + UInt64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
}

final class Segmenter: NSObject, SCStreamOutput, SCStreamDelegate {
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var partURL: URL?
  private var startedAt: CMTime = .invalid
  private let queue = DispatchQueue(label: "writer")
  var failed = false

  func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sb.isValid, complete(sb) else { return }
    queue.sync {
      let recording = FileManager.default.fileExists(atPath: flag.path) && backlogBytes() < MAX_BACKLOG
      let t = CMSampleBufferGetPresentationTimeStamp(sb)
      if !recording { finish(); return }
      if writer == nil { open(at: t) }
      if CMTimeGetSeconds(CMTimeSubtract(t, startedAt)) >= SEGMENT_SECONDS { finish(); open(at: t) }
      if let input, input.isReadyForMoreMediaData { input.append(sb) }
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    log("stream stopped: \(error.localizedDescription)")
    queue.sync { finish() }
    failed = true
  }

  private func complete(_ sb: CMSampleBuffer) -> Bool {
    guard let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let raw = atts.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return false }
    return status == .complete
  }

  private func open(at t: CMTime) {
    let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let url = outDir.appendingPathComponent("\(name).part")
    do {
      let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
      let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: WIDTH, AVVideoHeightKey: HEIGHT,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: BITRATE, AVVideoExpectedSourceFrameRateKey: FPS,
          AVVideoMaxKeyFrameIntervalKey: Int(FPS) * 2, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
      ])
      i.expectsMediaDataInRealTime = true
      w.add(i)
      w.startWriting()
      w.startSession(atSourceTime: t)
      writer = w; input = i; partURL = url; startedAt = t
      log("segment started \(url.lastPathComponent)")
    } catch { log("cannot open segment: \(error)") }
  }

  private func finish() {
    guard let w = writer, let i = input, let part = partURL else { return }
    writer = nil; input = nil; partURL = nil
    i.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    w.finishWriting { done.signal() }
    done.wait()
    let mp4 = part.deletingPathExtension().appendingPathExtension("mp4")
    try? FileManager.default.moveItem(at: part, to: mp4)
    log("segment finished \(mp4.lastPathComponent)")
  }

  func close() { queue.sync { finish() } }
}

func gameWindow() async -> SCWindow? {
  guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return nil }
  return content.windows
    .filter { ($0.owningApplication?.applicationName.lowercased().contains("luanti") ?? false) && $0.frame.width > 300 }
    .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}

// Capture the game window until it goes away, then look for it again: the game is restarted
// after sleep or a crash, and a new window must never be missed.
let seg = Segmenter()
signal(SIGTERM) { _ in seg.close(); exit(0) }
signal(SIGINT) { _ in seg.close(); exit(0) }
while true {
  guard let window = await gameWindow() else { try await Task.sleep(for: .seconds(5)); continue }
  let config = SCStreamConfiguration()
  config.width = WIDTH; config.height = HEIGHT
  config.minimumFrameInterval = CMTime(value: 1, timescale: FPS)
  config.showsCursor = false
  // Crop the title bar: a window's frame includes it, the game view is the rest.
  let titleBar = 28.0
  config.sourceRect = CGRect(x: 0, y: titleBar, width: window.frame.width, height: window.frame.height - titleBar)
  config.queueDepth = 6
  let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: seg)
  do {
    try stream.addStreamOutput(seg, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    try await stream.startCapture()
    log("capturing window \(window.windowID) \(Int(window.frame.width))x\(Int(window.frame.height))")
    seg.failed = false
    while !seg.failed, await gameWindow()?.windowID == window.windowID { try await Task.sleep(for: .seconds(5)) }
    try? await stream.stopCapture()
    seg.close()
  } catch {
    log("capture failed: \(error.localizedDescription)")
    try await Task.sleep(for: .seconds(5))
  }
}
