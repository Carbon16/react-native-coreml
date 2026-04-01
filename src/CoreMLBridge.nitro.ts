import type { HybridObject } from 'react-native-nitro-modules'

export interface CoreMLTensor {
  name: string
  shape: number[]
  values: number[]
  dataType: string
}

export interface CoreMLPredictRequest {
  modelId: string
  inputs: CoreMLTensor[]
  outputNames: string[]
}

export interface CoreMLPredictResult {
  outputs: CoreMLTensor[]
}

export interface CoreMLTrainingSample {
  inputs: CoreMLTensor[]
  outputs: CoreMLTensor[]
}

export interface CoreMLUpdateRequest {
  modelId: string
  samples: CoreMLTrainingSample[]
  saveToPath: string
}

export interface CoreMLUpdateResult {
  updatedModelPath: string
}

export type CoreMLExecutionMode = 'efficiency' | 'performance'

export interface CoreMLBridge extends HybridObject<{ ios: 'swift' }> {
  setExecutionMode(mode: CoreMLExecutionMode): void
  registerCompiledModel(modelId: string, compiledModelPath: string): void
  compileAndRegisterModel(modelId: string, mlmodelPath: string): Promise<string>
  preloadModel(modelId: string): Promise<void>
  predict(request: CoreMLPredictRequest): Promise<CoreMLPredictResult>
  updateModel(request: CoreMLUpdateRequest): Promise<CoreMLUpdateResult>
  unloadModel(modelId: string): void
  clearLoadedModels(): void
}
