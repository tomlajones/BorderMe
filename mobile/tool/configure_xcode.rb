#!/usr/bin/env ruby
# Wires Mat Board's native code into the Flutter-generated Xcode project.
# Safe to run repeatedly: it only adds what is missing.
#
#   "$(brew --prefix ruby)/bin/ruby" mobile/tool/configure_xcode.rb

require 'xcodeproj'

IOS_DIR = File.expand_path('../ios', __dir__)
project = Xcodeproj::Project.open(File.join(IOS_DIR, 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

def group_for(project, name, path)
  project.main_group.children.find { |c| c.display_name == name } ||
    project.main_group.new_group(name, path)
end

def reference_in(group, filename)
  group.files.find { |f| f.path == filename } || group.new_reference(filename)
end

def add_sources(group, target, filenames)
  filenames.each do |filename|
    target.source_build_phase.add_file_reference(reference_in(group, filename), true)
  end
end

ENGINE_FILES = %w[Settings.swift RenderPlan.swift Renderer.swift].freeze
SHARED_FILES = %w[SettingsStore.swift LibraryWriter.swift PickedFiles.swift FailureReason.swift].freeze
RUNNER_FILES = %w[EnginePlugin.swift PhotoPicker.swift BatchProcessor.swift].freeze

engine_group = group_for(project, 'BorderEngine', 'BorderEngine/Sources/BorderEngine')
shared_group = group_for(project, 'Shared', 'Shared')
runner_group = project.main_group.children.find { |c| c.display_name == 'Runner' } or abort('Runner group not found')

add_sources(engine_group, runner, ENGINE_FILES)
add_sources(shared_group, runner, SHARED_FILES)
add_sources(runner_group, runner, RUNNER_FILES)
runner.resources_build_phase.add_file_reference(reference_in(runner_group, 'PrivacyInfo.xcprivacy'), true)
reference_in(runner_group, 'Runner.entitlements')

runner.build_configurations.each do |config|
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1' # iPhone only; iPad runs it scaled
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.build_configurations.each do |config|
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end
project.targets.select { |t| t.name == 'RunnerTests' }.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  end
end

# --- Share extension ---

EXTENSION_NAME = 'ShareExtension'
EXTENSION_FILES = %w[ShareViewController.swift ShareModel.swift ShareView.swift].freeze

extension = project.targets.find { |t| t.name == EXTENSION_NAME }
unless extension
  extension = project.new_target(:app_extension, EXTENSION_NAME, :ios, '16.0')
  runner.add_dependency(extension)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13'
  embedded = embed.add_file_reference(extension.product_reference, true)
  embedded.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Flutter's "Thin Binary" script must run after the extension is embedded,
  # otherwise Xcode reports a dependency cycle in Runner.
  thin = runner.build_phases.find { |p| p.display_name == 'Thin Binary' }
  if thin
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index(thin), embed)
  end
end
extension.add_build_configuration('Profile', :release) unless extension.build_configurations.any? { |c| c.name == 'Profile' }

extension_group = group_for(project, EXTENSION_NAME, EXTENSION_NAME)
add_sources(extension_group, extension, EXTENSION_FILES)
add_sources(engine_group, extension, ENGINE_FILES)
add_sources(shared_group, extension, SHARED_FILES)
extension.resources_build_phase.add_file_reference(reference_in(extension_group, 'PrivacyInfo.xcprivacy'), true)
%w[Info.plist ShareExtension.entitlements].each { |f| reference_in(extension_group, f) }

# The extension shares Runner's Flutter xcconfig, which provides
# FLUTTER_BUILD_NAME and FLUTTER_BUILD_NUMBER, so both report the same version.
runner_bases = runner.build_configurations.to_h { |c| [c.name, c.base_configuration_reference] }
runner_team = runner.build_configurations.to_h { |c| [c.name, c.build_settings['DEVELOPMENT_TEAM']] }
extension.build_configurations.each do |config|
  config.base_configuration_reference = runner_bases[config.name] || runner_bases['Release']
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tomlajones.matboard.share'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  settings['DEVELOPMENT_TEAM'] = runner_team[config.name] if runner_team[config.name]
  settings['SKIP_INSTALL'] = 'YES'
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

project.save
puts 'Xcode project configured.'
