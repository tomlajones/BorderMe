#!/usr/bin/env ruby
# Wires BorderMe's native code into the Flutter-generated Xcode project.
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
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end
project.targets.select { |t| t.name == 'RunnerTests' }.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  end
end

# --- Share extension (added in Task 7) ---

project.save
puts 'Xcode project configured.'
