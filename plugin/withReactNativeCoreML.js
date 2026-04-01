const { withPodfileProperties } = require('@expo/config-plugins')

function compareVersions(a, b) {
  const aParts = String(a).split('.').map((p) => Number.parseInt(p, 10) || 0)
  const bParts = String(b).split('.').map((p) => Number.parseInt(p, 10) || 0)
  const maxLength = Math.max(aParts.length, bParts.length)

  for (let i = 0; i < maxLength; i += 1) {
    const aValue = aParts[i] ?? 0
    const bValue = bParts[i] ?? 0
    if (aValue > bValue) return 1
    if (aValue < bValue) return -1
  }

  return 0
}

const withReactNativeCoreML = (config, props = {}) => {
  const minIosDeploymentTarget = props.iosDeploymentTarget ?? '15.0'

  return withPodfileProperties(config, (configWithProps) => {
    const existingTarget = configWithProps.modResults['ios.deploymentTarget']

    if (!existingTarget || compareVersions(existingTarget, minIosDeploymentTarget) < 0) {
      configWithProps.modResults['ios.deploymentTarget'] = minIosDeploymentTarget
    }

    return configWithProps
  })
}

module.exports = withReactNativeCoreML
