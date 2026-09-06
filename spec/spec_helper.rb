# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'securerandom'
require 'simplecov'
require 'simplecov-cobertura'
require 'tmpdir'
require 'tty/platform'

SimpleCov.command_name 'RSpec'
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::CoberturaFormatter, SimpleCov::Formatter::HTMLFormatter]
  )
  cover 'lib/**/*.rb'
  enable_coverage :branch
  skip '/spec/'
end

RSpec.configure do |config|
  config.before(:suite) do
    all_spec_files = Dir[File.join(__dir__, '**', '*_spec.rb')].map { |path| File.expand_path(path) }.sort
    selected_spec_files = RSpec.configuration.files_to_run.map { |path| File.expand_path(path) }.sort
    unfiltered = [RSpec.configuration.inclusion_filter, RSpec.configuration.exclusion_filter].all? do |filter|
      filter.rules.empty?
    end

    SimpleCov.minimum_coverage line: 95, branch: 80 if unfiltered && selected_spec_files == all_spec_files
  end
end

module Helpers
  def hook_logger(&)
    require 'patchelf/logger'
    require 'patchelf/helper'

    allow(PatchELF::Helper).to receive(:color_enabled?) { false }
    # no method 'reopen' before ruby 2.3
    org_logger = PatchELF::Logger.instance_variable_get(:@logger)
    new_logger = ::Logger.new($stdout)
    new_logger.formatter = org_logger.formatter
    PatchELF::Logger.instance_variable_set(:@logger, new_logger)
    yield
  ensure
    PatchELF::Logger.instance_variable_set(:@logger, org_logger)
  end

  def with_tempfile
    filename = File.join(Dir.tmpdir, "patchelf-#{SecureRandom.hex(8)}")
    yield filename
  ensure
    FileUtils.rm_f(filename)
  end

  def bin_path(filename)
    File.join(__dir__, 'files', filename)
  end

  def linux_only!
    skip 'Linux only' unless TTY::Platform.new.linux?
  end
end

include Helpers
