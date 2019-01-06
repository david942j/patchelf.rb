require 'simplecov'
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [SimpleCov::Formatter::HTMLFormatter]
)
SimpleCov.start do
  add_filter '/spec/'
end

module Helpers
  def hook_logger(&_block)
    require 'patchelf/logger'
    require 'patchelf/helper'

    allow(PatchELF::Helper).to receive(:color_enabled?) { false }
    # no method 'reopen' before ruby 2.3
    org_logger = PatchELF::Logger.instance_variable_get(:@logger)
    new_logger = ::Logger.new($stdout)
    new_logger.formatter = org_logger.formatter
    PatchELF::Logger.instance_variable_set(:@logger, new_logger)
    ret = yield
    PatchELF::Logger.instance_variable_set(:@logger, org_logger)
    ret
  end

  def with_tempfile
    require 'tmpdir'
    require 'securerandom'
    require 'fileutils'
    filename = File.join(Dir.tmpdir, 'patchelf-' + SecureRandom.hex(8))
    yield filename
  ensure
    FileUtils.rm_f(filename)
  end
end

include Helpers
