#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint homography_opencv_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'homography_opencv_plugin'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for computing homography from matched points using OpenCV'
  s.description      = <<-DESC
A Flutter FFI plugin that provides homography computation using OpenCV.
Includes pre-built static libraries with OpenCV statically linked.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Use pre-built xcframework with static libraries (same name in all slices)
  s.vendored_frameworks = 'homography.xcframework'
  
  # Required system libraries
  s.libraries = 'c++', 'z'
  s.frameworks = 'Accelerate', 'CoreFoundation', 'CoreGraphics'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  
  # ObjC flag ensures categories are loaded
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC'
  }
  
  s.swift_version = '5.0'
end
