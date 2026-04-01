require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'react-native-coreml-nitro'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = 'https://github.com/your-org/react-native-coreml-nitro'
  s.license      = { :type => 'MIT' }
  s.authors      = package['author']
  s.platforms    = { :ios => '15.0' }
  s.source       = { :git => 'https://github.com/your-org/react-native-coreml-nitro.git', :tag => s.version.to_s }

  s.source_files = [
    'ios/**/*.{swift,h,m,mm,cpp}',
    'nitrogen/generated/ios/**/*.{swift,h,m,mm,cpp}'
  ]

  s.dependency 'React-Core'
  s.dependency 'NitroModules'

  load 'nitrogen/generated/ios/NitroCoreML+autolinking.rb'
  add_nitrogen_files(s)
end
