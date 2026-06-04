import Foundation
import llama

/// Singleton managing on-device LLM inference via llama.cpp (Qwen3-1.7B Q4_K_M).
final class LlamaCppManager: NSObject {
  static let shared = LlamaCppManager()

  // MARK: - Model config

  private let modelFileName = "Qwen3-1.7B-Q4_K_M.gguf"
  private let modelDownloadURL = URL(
    string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
  )!

  // MARK: - State

  private var model: OpaquePointer?                            // llama_model *
  private var context: OpaquePointer?                          // llama_context *
  private var sampler: UnsafeMutablePointer<llama_sampler>?    // llama_sampler *
  private let inferenceQueue = DispatchQueue(label: "com.pharmascanner.llama", qos: .userInitiated)

  private var downloadTask: URLSessionDownloadTask?
  private var downloadProgressHandler: ((Double) -> Void)?
  private var downloadCompletionHandler: ((Error?) -> Void)?
  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForResource = 3600
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private override init() {
    super.init()
  }

  // MARK: - Model file paths

  private var modelsDirectory: URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("Models")
  }

  private var modelFilePath: URL {
    modelsDirectory.appendingPathComponent(modelFileName)
  }

  // MARK: - Public API

  var isModelDownloaded: Bool {
    FileManager.default.fileExists(atPath: modelFilePath.path)
  }

  var isModelLoaded: Bool {
    model != nil && context != nil
  }

  /// Download the GGUF model from HuggingFace with progress reporting.
  func downloadModel(
    onProgress: @escaping (Double) -> Void,
    onComplete: @escaping (Error?) -> Void
  ) {
    guard !isModelDownloaded else {
      onComplete(nil)
      return
    }

    // Create Models directory if needed
    try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

    downloadProgressHandler = onProgress
    downloadCompletionHandler = onComplete

    let task = downloadSession.downloadTask(with: modelDownloadURL)
    downloadTask = task
    task.resume()
  }

  /// Cancel an in-progress download.
  func cancelDownload() {
    downloadTask?.cancel()
    downloadTask = nil
    downloadProgressHandler = nil
    downloadCompletionHandler = nil
  }

  /// Load the model into memory with Metal GPU acceleration.
  func loadModel() throws {
    guard isModelDownloaded else {
      throw LlamaError.modelNotFound
    }
    guard !isModelLoaded else { return }

    llama_backend_init()

    // Model params: offload all layers to Metal GPU
    var modelParams = llama_model_default_params()
    modelParams.n_gpu_layers = 99

    guard let loadedModel = llama_model_load_from_file(modelFilePath.path, modelParams) else {
      throw LlamaError.modelLoadFailed
    }
    model = loadedModel

    // Context params
    var ctxParams = llama_context_default_params()
    ctxParams.n_ctx = 4096
    ctxParams.n_batch = 512

    guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
      llama_model_free(loadedModel)
      self.model = nil
      throw LlamaError.contextCreationFailed
    }
    context = ctx

    // Create sampler chain
    let samplerChain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
    llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(0.1))
    llama_sampler_chain_add(samplerChain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
    sampler = samplerChain
  }

  /// Run inference on the given prompt. Returns the generated text.
  func generate(prompt: String) async throws -> String {
    guard let model = model, let context = context, let sampler = sampler else {
      throw LlamaError.modelNotLoaded
    }

    return try await withCheckedThrowingContinuation { continuation in
      inferenceQueue.async {
        do {
          let result = try self.runInference(
            prompt: prompt,
            model: model,
            context: context,
            sampler: sampler
          )
          continuation.resume(returning: result)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Unload model and free all resources.
  func unloadModel() {
    if let s = sampler {
      llama_sampler_free(s)
      sampler = nil
    }
    if let ctx = context {
      llama_free(ctx)
      context = nil
    }
    if let m = model {
      llama_model_free(m)
      model = nil
    }
    llama_backend_free()
  }

  /// Delete the downloaded model file from disk.
  func deleteModel() {
    unloadModel()
    try? FileManager.default.removeItem(at: modelFilePath)
  }

  // MARK: - Prompt building

  /// Build a Qwen3 ChatML prompt for structured data extraction.
  func buildPrompt(ocrText: String, jsonSchema: String) -> String {
    """
    <|im_start|>system
    You are a precise document data extraction assistant. Extract structured data from OCR text. Return ONLY valid JSON matching the schema. Do not include any explanation or markdown formatting./no_think<|im_end|>
    <|im_start|>user
    Extract data matching this JSON schema:
    \(jsonSchema)

    OCR TEXT:
    \(ocrText)<|im_end|>
    <|im_start|>assistant
    """
  }

  // MARK: - Private inference

  private func runInference(
    prompt: String,
    model: OpaquePointer,
    context: OpaquePointer,
    sampler: UnsafeMutablePointer<llama_sampler>
  ) throws -> String {
    // Clear KV cache
    llama_kv_cache_clear(context)

    // Tokenize prompt
    let promptCStr = prompt.cString(using: .utf8)!
    let maxTokens = Int32(prompt.utf8.count + 256)
    var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
    let vocab = llama_model_get_vocab(model)
    let nTokens = llama_tokenize(
      vocab,
      promptCStr,
      Int32(promptCStr.count - 1), // exclude null terminator
      &tokens,
      maxTokens,
      true,  // add_special
      true   // parse_special
    )

    guard nTokens > 0 else {
      throw LlamaError.tokenizationFailed
    }

    tokens = Array(tokens.prefix(Int(nTokens)))

    // Decode prefill in chunks of n_batch (512)
    let nBatch = 512
    var offset = 0
    while offset < tokens.count {
      let chunkSize = min(nBatch, tokens.count - offset)
      var chunk = Array(tokens[offset..<(offset + chunkSize)])
      var batch = llama_batch_get_one(&chunk, Int32(chunkSize))
      let prefillResult = llama_decode(context, batch)
      guard prefillResult == 0 else {
        throw LlamaError.decodeFailed
      }
      offset += chunkSize
    }

    // Autoregressive generation
    var output = ""
    let maxGenTokens = 2048
    let eosToken = llama_vocab_eos(vocab)

    for _ in 0..<maxGenTokens {
      let newTokenId = llama_sampler_sample(sampler, context, -1)

      // Check for end of sequence
      if newTokenId == eosToken || llama_vocab_is_eog(vocab, newTokenId) {
        break
      }

      // Convert token to text
      var buf = [CChar](repeating: 0, count: 256)
      let nChars = llama_token_to_piece(
        vocab,
        newTokenId,
        &buf,
        Int32(buf.count),
        0,
        true // special
      )

      if nChars > 0 {
        buf[Int(nChars)] = 0
        if let piece = String(cString: buf, encoding: .utf8) {
          output += piece
        }
      }

      // Prepare next batch with single token
      var nextToken = newTokenId
      var nextBatch = llama_batch_get_one(&nextToken, 1)
      let decodeResult = llama_decode(context, nextBatch)
      if decodeResult != 0 {
        break
      }
    }

    // Reset sampler state for next generation
    llama_sampler_reset(sampler)

    return output
  }
}

// MARK: - URLSessionDownloadDelegate

extension LlamaCppManager: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      // Create directory if needed
      try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

      // Remove existing file if any
      if FileManager.default.fileExists(atPath: modelFilePath.path) {
        try FileManager.default.removeItem(at: modelFilePath)
      }

      // Move downloaded file to final location
      try FileManager.default.moveItem(at: location, to: modelFilePath)

      DispatchQueue.main.async {
        self.downloadCompletionHandler?(nil)
        self.downloadProgressHandler = nil
        self.downloadCompletionHandler = nil
        self.downloadTask = nil
      }
    } catch {
      DispatchQueue.main.async {
        self.downloadCompletionHandler?(error)
        self.downloadProgressHandler = nil
        self.downloadCompletionHandler = nil
        self.downloadTask = nil
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    DispatchQueue.main.async {
      self.downloadProgressHandler?(progress)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error = error {
      DispatchQueue.main.async {
        self.downloadCompletionHandler?(error)
        self.downloadProgressHandler = nil
        self.downloadCompletionHandler = nil
        self.downloadTask = nil
      }
    }
  }
}

// MARK: - Errors

enum LlamaError: Error, LocalizedError {
  case modelNotFound
  case modelLoadFailed
  case contextCreationFailed
  case modelNotLoaded
  case tokenizationFailed
  case decodeFailed
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotFound:
      return "Model file not found. Please download the model first."
    case .modelLoadFailed:
      return "Failed to load the GGUF model file."
    case .contextCreationFailed:
      return "Failed to create llama context."
    case .modelNotLoaded:
      return "Model is not loaded. Call loadModel() first."
    case .tokenizationFailed:
      return "Failed to tokenize the prompt."
    case .decodeFailed:
      return "Failed to decode tokens."
    case .generationFailed(let msg):
      return "Generation failed: \(msg)"
    }
  }
}
