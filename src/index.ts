import { NitroModules } from 'react-native-nitro-modules'
import type { CoreMLBridge } from './CoreMLBridge.nitro'

export type {
  CoreMLBridge,
  CoreMLPredictRequest,
  CoreMLPredictResult,
  CoreMLTensor,
  CoreMLTrainingSample,
  CoreMLUpdateRequest,
  CoreMLUpdateResult,
} from './CoreMLBridge.nitro'

export const CoreML = NitroModules.createHybridObject<CoreMLBridge>('CoreMLBridge')
