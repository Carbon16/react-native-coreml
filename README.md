# react-native-coreml-nitro

High-performance React Native Nitro bridge for CoreML with runtime model updates.

This package is designed for iOS apps.

## Features

- Run CoreML models from JavaScript.
- Update updatable CoreML models at runtime.
- Choose execution mode at runtime:
   - `efficiency`: lower battery and memory pressure.
   - `performance`: higher throughput and lower latency.
- Preload models to reduce first-inference latency.
- Asynchronous native work to keep the JS thread responsive.

## Installation

1. Install package dependencies in your module/app workspace.

```bash
bun install
```

2. Generate Nitro bindings.

```bash
bunx nitrogen
```

3. In your iOS app, run pods.

```bash
cd ios
pod install
```

## Expo Config Plugin

This package ships with an Expo config plugin.

### SDK 52+ `app.json` Example

For Expo SDK 52 and newer, use a plugin entry in `expo.plugins`.

```json
{
   "expo": {
      "plugins": [
         [
            "react-native-coreml-nitro",
            {
               "iosDeploymentTarget": "15.0"
            }
         ]
      ]
   }
}
```

This is the recommended SDK 52+ pattern for native module config plugins.

### Plugin Usage

Add it in your app config:

```json
{
   "expo": {
      "plugins": [
         [
            "react-native-coreml-nitro",
            {
               "iosDeploymentTarget": "15.0"
            }
         ]
      ]
   }
}
```

What it does:

- Ensures `ios.deploymentTarget` is at least the value you configure (default: `15.0`).
- Leaves higher existing deployment targets unchanged.

After adding the plugin, run:

```bash
npx expo prebuild -p ios
```

## Quick Start

```ts
import { CoreML } from './src'

// 1) choose runtime mode
CoreML.setExecutionMode('efficiency')

// 2) register model (.mlmodelc directory)
CoreML.registerCompiledModel('classifier', '/absolute/path/MyModel.mlmodelc')

// Optional: warm model to reduce first prediction latency
await CoreML.preloadModel('classifier')

// 3) run prediction
const result = await CoreML.predict({
   modelId: 'classifier',
   outputNames: [],
   inputs: [
      {
         name: 'input',
         shape: [1, 3, 224, 224],
         values: [],
         dataType: 'float32',
      },
   ],
})
```

## API

### `setExecutionMode(mode)`

`mode: 'efficiency' | 'performance'`

- `efficiency` (default): CPU-only and minimal in-memory cache.
- `performance`: enables broader compute units and larger in-memory cache.

### `registerCompiledModel(modelId, compiledModelPath)`

Registers an existing `.mlmodelc` path with an id.

### `compileAndRegisterModel(modelId, mlmodelPath)`

Compiles a `.mlmodel` file and registers the resulting compiled model.

Returns the compiled model path.

### `preloadModel(modelId)`

Loads the model once into native cache for faster first prediction.

### `predict(request)`

Runs async inference and returns output tensors.

### `updateModel(request)`

Runs CoreML update task for updatable models and saves the updated model to `saveToPath`.

### `unloadModel(modelId)` and `clearLoadedModels()`

Releases native model cache to reduce memory pressure.

## Efficiency vs Performance

CoreML does not expose a direct API to pin work to efficiency cores vs performance cores.
The module exposes practical modes by tuning CoreML configuration and cache behavior:

- `efficiency`
   - `MLComputeUnits.cpuOnly`
   - minimal model cache
   - best for battery-sensitive or background use
- `performance`
   - `MLComputeUnits.all`
   - larger model cache
   - lower latency and higher throughput