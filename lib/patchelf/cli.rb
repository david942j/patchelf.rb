require 'optparse'

require 'patchelf/patcher'
require 'patchelf/version'

module PatchELF
  # For command line interface to parsing arguments.
  module CLI
    # Name of binary.
    SCRIPT_NAME = 'patchelf.rb'.freeze
    # CLI usage string.
    USAGE = format('Usage: %s <commands> FILENAME [OUTPUT_FILE]', SCRIPT_NAME).freeze

    module_function

    # Main method of CLI.
    # @param [Array<String>] argv
    #   Command line arguments.
    # @return [void]
    # @example
    #   PatchELF::CLI.work(%w[--help])
    #   # usage message to stdout
    #   PatchELF::CLI.work(%w[--version])
    #   # version message to stdout
    def work(argv)
      @options = {
        set: {},
        print: []
      }
      return $stdout.puts "PatchELF Version #{PatchELF::VERSION}" if argv.include?('--version')
      return $stdout.puts option_parser unless parse(argv)

      # Now the options are (hopefully) valid, let's process the ELF file.
      patcher = PatchELF::Patcher.new(@options[:in_file])
      # TODO: Handle ELFTools::ELFError
      @options[:print].uniq.each do |s|
        content = patcher.get(s)
        next if content.nil?

        $stdout.puts "#{s.to_s.capitalize}: #{Array(content).join(' ')}"
      end

      @options[:set].each do |sym, val|
        patcher.__send__("#{sym}=".to_sym, val)
      end

      patcher.save(@options[:out_file])
    end

    private

    def parse(argv)
      remain = option_parser.permute(argv)
      return false if remain.first.nil?

      @options[:in_file] = remain.first
      @options[:out_file] = remain[1] # can be nil
      true
    end

    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = USAGE

        opts.on('--pi', '--print-interpreter', 'Show interpreter\'s name.') do
          @options[:print] << :interpreter
        end

        opts.on('--pn', '--print-needed', 'Show needed libraries specified in DT_NEEDED.') do
          @options[:print] << :needed
        end

        opts.on('--ps', '--print-soname', 'Show soname specified in DT_SONAME.') do
          @options[:print] << :soname
        end

        opts.on('--si INTERP', '--set-interpreter INTERP', 'Set interpreter\'s name.') do |interp|
          @options[:set][:interpreter] = interp
        end

        opts.on('--version', 'Show current gem\'s version.') {}
      end
    end

    extend self
  end
end
