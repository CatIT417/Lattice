# frozen_string_literal: true

source "https://rubygems.org"

gem 'fastlane', '>= 2.228.0'

# Until Fastlane includes them directly.
gem 'nkf'
gem 'abbrev'
gem 'mutex_m'
gem 'ostruct'


plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
