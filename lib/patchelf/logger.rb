require 'logger'

require 'patchelf/helper'

module PatchELF
  # A logger for internal usage.
  module Logger
    module_function

    # Get the logger object.
    # @return [::Logger]
    #   A logger that logs to stderr.
    def logger
      @logger ||= ::Logger.new($stderr).tap do |log|
        log.formatter = proc do |severity, _datetime, _progname, msg|
          "[#{PatchELF::Helper.colorize(severity, severity.downcase.to_sym)}] #{msg}\n"
        end
      end
    end

    %i[info warn error].each do |sym|
      define_method(sym) do |msg|
        logger.__send__(sym, msg)
      end
    end
  end
end
