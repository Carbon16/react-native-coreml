import Foundation
import CoreML

final class HybridCoreMLBridge: HybridCoreMLBridgeSpec {
  private enum ExecutionMode: String {
    case efficiency
    case performance

    var computeUnits: MLComputeUnits {
      switch self {
      case .efficiency:
        return .cpuOnly
      case .performance:
        return .all
      }
    }

    var allowLowPrecisionAccumulationOnGPU: Bool {
      switch self {
      case .efficiency:
        return false
      case .performance:
        return true
      }
    }

    static func parse(_ value: String) -> ExecutionMode {
      switch value {
      case "efficiency", "lowPower", "balanced":
        return .efficiency
      case "performance":
        return .performance
      default:
        return .efficiency
      }
    }
  }

  private let queue = DispatchQueue(label: "coreml.bridge.queue", qos: .utility)

  private var mode: ExecutionMode = .efficiency
  private var registeredModelURLs: [String: URL] = [:]
  private var modelCache: [String: MLModel] = [:]
  private var modelUseOrder: [String] = []
  private var maxLoadedModels = 1

  func setExecutionMode(mode: String) {
    queue.sync {
      self.mode = ExecutionMode.parse(mode)
      self.maxLoadedModels = self.mode == .efficiency ? 1 : 3
      self.trimCacheIfNeeded()
    }
  }

  func registerCompiledModel(modelId: String, compiledModelPath: String) throws {
    let url = URL(fileURLWithPath: compiledModelPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw RuntimeError.error(withMessage: "Compiled model path does not exist: \(compiledModelPath)")
    }

    queue.sync {
      self.registeredModelURLs[modelId] = url
      self.modelCache.removeValue(forKey: modelId)
      self.modelUseOrder.removeAll(where: { $0 == modelId })
    }
  }

  func compileAndRegisterModel(modelId: String, mlmodelPath: String) throws -> Promise<String> {
    return Promise.async {
      let sourceURL = URL(fileURLWithPath: mlmodelPath)
      guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw RuntimeError.error(withMessage: "Model file not found: \(mlmodelPath)")
      }

      let compiledURL = try MLModel.compileModel(at: sourceURL)

      self.queue.sync {
        self.registeredModelURLs[modelId] = compiledURL
        self.modelCache.removeValue(forKey: modelId)
        self.modelUseOrder.removeAll(where: { $0 == modelId })
      }

      return compiledURL.path
    }
  }

  func preloadModel(modelId: String) throws -> Promise<Void> {
    return Promise.async {
      _ = try self.getOrLoadModel(for: modelId)
    }
  }

  func predict(request: CoreMLPredictRequest) throws -> Promise<CoreMLPredictResult> {
    return Promise.async {
      let model = try self.getOrLoadModel(for: request.modelId)

      let inputFeatures = try self.makeFeatureProvider(from: request.inputs)
      let prediction = try model.prediction(from: inputFeatures)

      let outputNames = request.outputNames.isEmpty ? prediction.featureNames.sorted() : request.outputNames
      var outputs: [CoreMLTensor] = []
      outputs.reserveCapacity(outputNames.count)

      for outputName in outputNames {
        guard let value = prediction.featureValue(for: outputName) else {
          continue
        }
        if let tensor = try self.featureValueToTensor(name: outputName, value: value) {
          outputs.append(tensor)
        }
      }

      return CoreMLPredictResult(outputs: outputs)
    }
  }

  func updateModel(request: CoreMLUpdateRequest) throws -> Promise<CoreMLUpdateResult> {
    return Promise.async {
      guard !request.samples.isEmpty else {
        throw RuntimeError.error(withMessage: "Update requires at least one training sample")
      }

      let modelURL = try self.requireRegisteredModelURL(for: request.modelId)
      let samples = try request.samples.map { sample in
        try self.makeTrainingFeatureProvider(sample: sample)
      }
      let batchProvider = MLArrayBatchProvider(array: samples)

      var resultPath = ""
      var updateError: Error?
      let semaphore = DispatchSemaphore(value: 0)

      let configuration = MLModelConfiguration()
      configuration.computeUnits = self.mode.computeUnits
      configuration.allowLowPrecisionAccumulationOnGPU = self.mode.allowLowPrecisionAccumulationOnGPU

      let task = try MLUpdateTask(forModelAt: modelURL, trainingData: batchProvider, configuration: configuration) { context in
        do {
          let saveURL = URL(fileURLWithPath: request.saveToPath)
          try context.model.write(to: saveURL)
          resultPath = saveURL.path
        } catch {
          updateError = error
        }
        semaphore.signal()
      }

      task.resume()
      semaphore.wait()

      if let updateError = updateError {
        throw updateError
      }

      if resultPath.isEmpty {
        throw RuntimeError.error(withMessage: "CoreML update did not produce an updated model")
      }

      self.queue.sync {
        self.registeredModelURLs[request.modelId] = URL(fileURLWithPath: resultPath)
        self.modelCache.removeValue(forKey: request.modelId)
        self.modelUseOrder.removeAll(where: { $0 == request.modelId })
      }

      return CoreMLUpdateResult(updatedModelPath: resultPath)
    }
  }

  func unloadModel(modelId: String) {
    queue.sync {
      self.modelCache.removeValue(forKey: modelId)
      self.modelUseOrder.removeAll(where: { $0 == modelId })
    }
  }

  func clearLoadedModels() {
    queue.sync {
      self.modelCache.removeAll(keepingCapacity: true)
      self.modelUseOrder.removeAll(keepingCapacity: true)
    }
  }

  private func requireRegisteredModelURL(for modelId: String) throws -> URL {
    return try queue.sync {
      guard let url = self.registeredModelURLs[modelId] else {
        throw RuntimeError.error(withMessage: "No registered model found for id: \(modelId)")
      }
      return url
    }
  }

  private func getOrLoadModel(for modelId: String) throws -> MLModel {
    if let cached = queue.sync(execute: { self.modelCache[modelId] }) {
      queue.sync {
        self.touchModelUseOrder(modelId)
      }
      return cached
    }

    let modelURL = try requireRegisteredModelURL(for: modelId)
    let configuration = MLModelConfiguration()
    let selectedMode = queue.sync { self.mode }
    configuration.computeUnits = selectedMode.computeUnits
    configuration.allowLowPrecisionAccumulationOnGPU = selectedMode.allowLowPrecisionAccumulationOnGPU

    let model = try MLModel(contentsOf: modelURL, configuration: configuration)

    queue.sync {
      self.modelCache[modelId] = model
      self.touchModelUseOrder(modelId)
      self.trimCacheIfNeeded()
    }

    return model
  }

  private func touchModelUseOrder(_ modelId: String) {
    modelUseOrder.removeAll(where: { $0 == modelId })
    modelUseOrder.append(modelId)
  }

  private func trimCacheIfNeeded() {
    while modelUseOrder.count > maxLoadedModels {
      let removeId = modelUseOrder.removeFirst()
      modelCache.removeValue(forKey: removeId)
    }
  }

  private func makeFeatureProvider(from tensors: [CoreMLTensor]) throws -> MLFeatureProvider {
    var dictionary: [String: MLFeatureValue] = [:]
    dictionary.reserveCapacity(tensors.count)

    for tensor in tensors {
      dictionary[tensor.name] = try MLFeatureValue(multiArray: makeMultiArray(from: tensor))
    }

    return try MLDictionaryFeatureProvider(dictionary: dictionary)
  }

  private func makeTrainingFeatureProvider(sample: CoreMLTrainingSample) throws -> MLFeatureProvider {
    var dictionary: [String: MLFeatureValue] = [:]
    dictionary.reserveCapacity(sample.inputs.count + sample.outputs.count)

    for tensor in sample.inputs {
      dictionary[tensor.name] = try MLFeatureValue(multiArray: makeMultiArray(from: tensor))
    }

    for tensor in sample.outputs {
      dictionary[tensor.name] = try MLFeatureValue(multiArray: makeMultiArray(from: tensor))
    }

    return try MLDictionaryFeatureProvider(dictionary: dictionary)
  }

  private func makeMultiArray(from tensor: CoreMLTensor) throws -> MLMultiArray {
    let shape = tensor.shape.map { NSNumber(value: Int($0)) }
    let elementCount = shape.reduce(1) { partialResult, number in
      partialResult * max(1, number.intValue)
    }

    guard elementCount == tensor.values.count else {
      throw RuntimeError.error(withMessage: "Tensor size mismatch for \(tensor.name). Expected \(elementCount), got \(tensor.values.count)")
    }

    let dataTypeLower = tensor.dataType.lowercased()
    let type: MLMultiArrayDataType = dataTypeLower == "float32" ? .float32 : .double
    let array = try MLMultiArray(shape: shape, dataType: type)

    switch type {
    case .float32:
      let pointer = UnsafeMutablePointer<Float32>(OpaquePointer(array.dataPointer))
      for index in 0..<tensor.values.count {
        pointer[index] = Float32(tensor.values[index])
      }
    default:
      let pointer = UnsafeMutablePointer<Double>(OpaquePointer(array.dataPointer))
      for index in 0..<tensor.values.count {
        pointer[index] = tensor.values[index]
      }
    }

    return array
  }

  private func featureValueToTensor(name: String, value: MLFeatureValue) throws -> CoreMLTensor? {
    guard let multiArray = value.multiArrayValue else {
      return nil
    }

    let shape = multiArray.shape.map { Double($0.intValue) }
    let count = multiArray.count
    var values: [Double] = []
    values.reserveCapacity(count)

    switch multiArray.dataType {
    case .float32:
      let pointer = UnsafeMutablePointer<Float32>(OpaquePointer(multiArray.dataPointer))
      for index in 0..<count {
        values.append(Double(pointer[index]))
      }
      return CoreMLTensor(name: name, shape: shape, values: values, dataType: "float32")
    default:
      let pointer = UnsafeMutablePointer<Double>(OpaquePointer(multiArray.dataPointer))
      for index in 0..<count {
        values.append(pointer[index])
      }
      return CoreMLTensor(name: name, shape: shape, values: values, dataType: "double")
    }
  }
}
