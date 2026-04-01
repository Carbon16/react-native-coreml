const { createRunOncePlugin } = require('@expo/config-plugins')
const withReactNativeCoreML = require('./plugin/withReactNativeCoreML')
const pkg = require('./package.json')

const withPlugin = (config, props) => {
  return withReactNativeCoreML(config, props)
}

module.exports = createRunOncePlugin(withPlugin, pkg.name, pkg.version)
