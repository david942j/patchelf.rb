require 'optparse'

require 'patchelf/patcher'

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
        print: []
      }
      parse(argv)
      # Now the options are (hopefully) valid, let's process the ELF file.
      patcher = PatchELF::Patcher.new(@options[:in_file])
      @options[:print].uniq.each do |s|
        content = patcher.print(s)
        next if content.nil?

        $stdout.puts "#{s.to_s.capitalize}: #{Array(content).join(', ')}"
      end
    end

    private

    def parse(argv)
      remain = option_parser.permute(argv)
      usage_and_exit if remain.first.nil?
      @options[:in_file] = remain.first
      @options[:out_file] = remain[1] || @options[:in_file]
    end

    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = USAGE

        opts.on('--print-interpreter', 'Show interpreter\'s name.') do
          @options[:print] << :interpreter
        end

        opts.on('--print-needed', 'Show needed libraries specified in DT_NEEDED.') do
          @options[:print] << :needed
        end

        opts.on('--print-soname', 'Show soname specified in DT_SONAME.') do
          @options[:print] << :soname
        end

        opts.on('--set-interpreter INTERP', 'Set interpreter\'s name.') do |interp|
          @options[:interp] = interp
        end

        opts.on('--version', 'Current gem version.') do
          puts "PatchELF version #{PatchELF::VERSION}"
          exit(0)
        end
      end
    end

    def usage_and_exit
      puts option_parser
      exit(1)
    end

    extend self
  end
end
