//
//  AIAssistant.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/12/23.
//

import UIKit

public class AIAssistant: NSObject {
    public enum NetworkConfiguration {
        case normal
        case backgroundData
        case backgroundUpload
    }

    public enum Mode {
        case assistant
        case translator
    }

    private static let _maxTokens = 4000    // 4096 for gpt-3.5-turbo and larger for gpt-4, but we use a conservative number to avoid hitting that limit

    private struct CompletionData {
        let completion: (String, String, AIError?) -> Void
        let wasAudioPrompt: Bool
    }

    private var _session: URLSession!
    private var _completionByTask: [Int: CompletionData] = [:]
    private var _tempFileURL: URL?

    private static let _assistantPrompt = "You are a smart assistant that answers all user queries, questions, and statements with a single sentence."
    private static let _translatorPrompt = "You are a smart assistant that translates user input to English. Translate as faithfully as you can and do not add any other commentary."

    private var _payload: [String: Any] = [
        "model": "gpt-4-vision-preview",
        "messages": [
            [
                "role": "system",
                "content": ""   // remember to set
            ]
        ]
    ]
    
    private var incomingData: Data?

    public init(configuration: NetworkConfiguration) {
        super.init()

        switch configuration {
        case .normal:
            _session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        case .backgroundUpload:
            // Background upload tasks use a file (uploadTask() can only be called from background
            // with a file)
            _tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
            fallthrough
        case .backgroundData:
            // Configure a URL session that supports background transfers
            let configuration = URLSessionConfiguration.background(withIdentifier: "ChatGPT-\(UUID().uuidString)")
            configuration.isDiscretionary = false
            configuration.shouldUseExtendedBackgroundIdleMode = true
            configuration.sessionSendsLaunchEvents = true
            configuration.allowsConstrainedNetworkAccess = true
            configuration.allowsExpensiveNetworkAccess = true
            _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
    }

    public func clearHistory() {
        // To clear history, remove all but the very first message
        if var messages = _payload["messages"] as? [[String: String]],
           messages.count > 1 {
            messages.removeSubrange(1..<messages.count)
            _payload["messages"] = messages
            print("[AIAssistant] Cleared history")
        }
    }

    public func sendImageToVision(
      imageURL: String, model: String, completion: @escaping (String, String, AIError?) -> Void
    ) {
      // Prepare URL request
      let url = URL(string: "https://api.openai.com/v1/chat/completions")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer " + brilliantAPIKey, forHTTPHeaderField: "Authorization")

      // Prepare the JSON payload
      let payload: [String: Any] = [
        "model": model,
        "messages": [
          [
            "role": "user",
            "content": [
              [
                "type": "text",
                "text": "What’s in this image?"
              ],
              [
                "type": "image_url",
                "image_url": [
                  "url": imageURL
                ]
              ]
            ]
          ]
        ],
        "max_tokens": 300,
        "stream": false
      ]

      // Convert the payload to JSON data
      guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
        completion("", "", AIError.internalError(message: "Internal error: Payload cannot be serialized"))
        return
      }

      // Attach the JSON data to the request
      request.httpBody = jsonData

      // Create task
    //   let task = _session.dataTask(with: request) { (data, response, error) in
    //     if let error = error {
    //         completion("", AIError.clientSideNetworkError(error: error))
    //     } else if let data = data {
    //         // Parse the response data
    //         let (response, error, _, _) = self.extractContent(from: data)
    //         completion(response as! String ?? "", error)
    //     }
    // }
    let task = _session.dataTask(with: request)

        
        // Associate completion handler with this task
    _completionByTask[task.taskIdentifier] = CompletionData(completion: completion, wasAudioPrompt: false)

      // Begin
      task.resume()
    }

    public func send(mode: Mode, audio: Data, model: String, completion: @escaping (String, String, AIError?) -> Void) {
        send(mode: mode, audio: audio, query: nil, model: model, completion: completion)
    }

    public func send(mode: Mode, query: String, model: String, completion: @escaping (String, String, AIError?) -> Void) {
        send(mode: mode, audio: nil, query: query, model: model, completion: completion)
    }

    private func send(mode: Mode, audio: Data?, query: String?, model: String, completion: @escaping (String, String, AIError?) -> Void) {
        // Either audio or text prompt only
        if audio != nil && query != nil {
            fatalError("ChatGPT.send() cannot have both audio and text prompts")
        } else if audio == nil && query == nil {
            fatalError("ChatGPT.send() must have either an audio or text prompt")
        }

        let boundary = UUID().uuidString

        // Set up conversation details and append user prompt if we know it now. If input is audio,
        // we will not be able to do this until we get the response.
        _payload["model"] = model
        setSystemPrompt(for: mode)
        if let query = query {
            appendUserQueryToChatSession(query: query)
        }

        guard let historyPayload = try? JSONSerialization.data(withJSONObject: _payload) else {
            completion("", "", AIError.internalError(message: "Internal error: Conversation history cannot be serialized"))
            return
        }

        // Build request
        let requestHeader = [
            "Authorization": brilliantAPIKey,
            "Content-Type": "multipart/form-data;boundary=\(boundary)"
        ]
        let service = audio != nil ? "audio_gpt" : "chat_gpt"
        let url = URL(string: "https://api.brilliant.xyz/noa/\(service)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeader

        // Form data
        var formData = Data()

        // Conversation history thus far using "json" field. If no audio, this must also contain
        // the current user query.
        formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition:form-data;name=\"json\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type:application/json\r\n\r\n".data(using: .utf8)!)
        formData.append(historyPayload)
        formData.append("\r\n".data(using: .utf8)!)

        // Audio data representing next user query
        if let audio = audio {
            formData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition:form-data;name=\"audio\";filename=\"audio.m4a\"\r\n".data(using: .utf8)!)  // TODO: temperature?
            formData.append("Content-Type:audio/m4a\r\n\r\n".data(using: .utf8)!)
            formData.append(audio)
            formData.append("\r\n".data(using: .utf8)!)
        }

        // Terminate form data
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // If this is a background task using a file, write that file, else attach to request
        if let fileURL = _tempFileURL {
            // TODO: error handling
            try? formData.write(to: fileURL)
        } else {
            request.httpBody = formData
        }

        // Create task
        let task = _tempFileURL == nil ? _session.dataTask(with: request) : _session.uploadTask(with: request, fromFile: _tempFileURL!)

        // Associate completion handler with this task
        _completionByTask[task.taskIdentifier] = CompletionData(completion: completion, wasAudioPrompt: true)

        // Begin
        task.resume()
    }

    private func setSystemPrompt(for mode: Mode) {
        if var messages = _payload["messages"] as? [[String: String]],
           messages.count >= 1 {
            messages[0]["content"] = mode == .assistant ? Self._assistantPrompt : Self._translatorPrompt
            _payload["messages"] = messages
        }
    }

    private func appendUserQueryToChatSession(query: String) {
        if var messages = _payload["messages"] as? [[String: String]] {
            // Append user prompts to maintain some sort of state. Note that we do not send back the agent responses because
            // they won't add much.
            messages.append([ "role": "user", "content": "\(query)" ])
            _payload["messages"] = messages
        }
    }

    private func appendAIResponseToChatSession(response: String) {
        if var messages = _payload["messages"] as? [[String: String]] {
            messages.append([ "role": "assistant", "content": "\(response)" ])
            _payload["messages"] = messages
        }
    }

    private func printConversation() {
        // Debug log conversation history
        print("---")
        for message in (_payload["messages"] as! [[String: String]]) {
            print("  role=\(message["role"]!), content=\(message["content"]!)")
        }
        print("---")
    }

    private func extractContent(from data: Data) -> (Any?, AIError?, String?, String?) {
        do {
            let jsonString = String(decoding: data, as: UTF8.self)
            if jsonString.count > 0 {
                print("[AIAssistant] Response payload: \(jsonString)")
            }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let response = json as? [String: AnyObject] {
                if let errorMessage = response["message"] as? String {
                   return (json, AIError.apiError(message: "Error from service: \(errorMessage)"), nil, nil)
                } else if let choices = response["choices"] as? [AnyObject],
                          choices.count > 0,
                          let first = choices[0] as? [String: AnyObject],
                          let message = first["message"] as? [String: AnyObject],
                          let assistantResponse = message["content"] as? String,
                          let userQuery = response["prompt"] as? String {
                    return (json, nil, userQuery, assistantResponse)
                }
            }
            print("[AIAssistant] Error: Unable to parse response")
        } catch {
            print("[AIAssistant] Error: Unable to deserialize response: \(error)")
        }
        return (nil, AIError.responsePayloadParseError, nil, nil)
    }

    private func extractTotalTokensUsed(from json: Any?) -> Int {
        if let json = json,
           let response = json as? [String: AnyObject],
           let usage = response["usage"] as? [String: AnyObject],
           let totalTokens = usage["total_tokens"] as? Int {
            return totalTokens
        }
        return 0
    }
}

extension AIAssistant: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        let errorMessage = error == nil ? "unknown error" : error!.localizedDescription
        print("[AIAssistant] URLSession became invalid: \(errorMessage)")

        // Deliver error for all outstanding tasks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (_, completionData) in self._completionByTask {
                completionData.completion("", "", AIError.clientSideNetworkError(error: error))
            }
            _completionByTask = [:]
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        print("[AIAssistant] URLSession finished events")
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[AIAssistant] URLSession received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[AIAssistant] URLSession unable to use credential")
        }
    }
}

extension AIAssistant: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
        print("[AIAssistant] URLSessionDataTask became stream task")
        streamTask.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
        print("[AIAssistant] URLSessionDataTask became download task")
        downloadTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("[AIAssistant] URLSessionDataTask received challenge")
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            print("[AIAssistant] URLSessionDataTask unable to use credential")

            // Deliver error
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let completionData = self._completionByTask[task.taskIdentifier] {
                    completionData.completion("", "", AIError.urlAuthenticationFailed)
                    self._completionByTask.removeValue(forKey: task.taskIdentifier)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Original request was redirected somewhere else. Create a new task for redirection.
        if let urlString = request.url?.absoluteString {
            print("[AIAssistant] URLSessionDataTask redirected to \(urlString)")
        } else {
            print("[AIAssistant] URLSessionDataTask redirected")
        }

        // New task
        let newTask = self._session.dataTask(with: request)

        // Replace completion
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completion = self._completionByTask[task.taskIdentifier] {
                self._completionByTask.removeValue(forKey: task.taskIdentifier) // out with the old
                self._completionByTask[newTask.taskIdentifier] = completion     // in with the new
            }
        }

        // Continue with new task
        newTask.resume()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[AIAssistant] URLSessionDataTask failed to complete: \(error.localizedDescription)")
        } else {
            // Error == nil should indicate successful completion
            print("[AIAssistant] URLSessionDataTask finished")
        }

        // If there really was no error, we should have received data, triggered the completion,
        // and removed the completion. If it's still hanging around, there must be some unknown
        // error or I am interpreting the task lifecycle incorrectly.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let completionData = self._completionByTask[task.taskIdentifier] {
                completionData.completion("", "", AIError.clientSideNetworkError(error: error))
                self._completionByTask.removeValue(forKey: task.taskIdentifier)
            }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Assume that regardless of any error (including non-200 status code), the didCompleteWithError
        // delegate method will eventually be called and we can report the error there
        print("[AIAssistant] URLSessionDataTask received response headers")
        guard let response = response as? HTTPURLResponse else {
            print("[AIAssistant] URLSessionDataTask received unknown response type")
            return
        }
        print("[AIAssistant] URLSessionDataTask received response code \(response.statusCode)")
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if incomingData == nil {
            incomingData = Data()
        }
        incomingData?.append(data)
        //var (json, contentError, userPrompt, response) = extractContent(from: incomingData!)
        //let userPromptString = userPrompt ?? ""
        //let responseString = response ?? "" // if response is nill, contentError will be set
        //let totalTokensUsed = extractTotalTokensUsed(from: json)

        // Deliver response and append to chat session
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let completionData = self._completionByTask[dataTask.taskIdentifier] else { return }

            let d = String(decoding: incomingData!, as: UTF8.self)
            appendAIResponseToChatSession(response: d)
            /*
            // Append to chat session to maintain running dialog unless we've exceeded the context
            // window
            if totalTokensUsed >= Self._maxTokens {
                clearHistory()
                print("[AIAssistant] Cleared context history because total tokens used reached \(totalTokensUsed)")
            } else {
                // Append the user prompt when in audio mode because we don't know the prompt until
                // we get the full response back
                if userPromptString.count > 0 && completionData.wasAudioPrompt {
                    appendUserQueryToChatSession(query: userPromptString)
                }

                
                // And also the response
                if let response = response {
                    appendAIResponseToChatSession(response: response)
                }
            }
             */
            // Deliver response
            if let completionData = self._completionByTask[dataTask.taskIdentifier] {
                completionData.completion("", d, nil)

                // User prompt delivered in
                //completionData.completion(userPromptString, responseString, contentError)
                self._completionByTask.removeValue(forKey: dataTask.taskIdentifier)
            } else {
                print("[AIAssistant]: Error: No completion found for task \(dataTask.taskIdentifier)")
            }
             
        }
    }
}
