import AVFoundation
import Foundation
import Speech

class SpeechRecognition: NSObject {
  private var _recognizer: SFSpeechRecognizer!

  public init(locale: Locale = Locale.current) {
    super.init()
    _recognizer = SFSpeechRecognizer(locale: locale)
    SFSpeechRecognizer.requestAuthorization { (authStatus) in
      if authStatus != .authorized {
        print("Speech recognition authorization failed")
      }
    }
    if !_recognizer.isAvailable {
      print("Speech recognizer not available for the current locale")
    }
  }

  public func translate(fileData: Data, completion: @escaping (String, Error?) -> Void) {

    let audioFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
    let audioBuffer = AVAudioPCMBuffer(
      pcmFormat: audioFormat, frameCapacity: UInt32(fileData.count / 2))!
    fileData.withUnsafeBytes {
      audioBuffer.floatChannelData!.pointee.update(from: $0, count: fileData.count / 2)
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    // request.audioBuffer = audioBuffer
    request.append(audioBuffer)
    _recognizer.recognitionTask(with: request) { (result, error) in
      DispatchQueue.main.async {
        if let error = error {
          print("Recognition error: \(error)")
        }
        let transcript = result?.bestTranscription.formattedString ?? ""
        print("transcript: \(transcript)")
        completion(transcript, error)
      }
    }
  }
}
