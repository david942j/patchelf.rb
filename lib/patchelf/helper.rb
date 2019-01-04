module PatchELF
  # Helper methods for internal usage.
  module Helper
    module_function

    # Color codes for pretty print.
    COLOR_CODE = {
      esc_m: "\e[0m",
      info: "\e[38;5;82m", # light green
      warn: "\e[38;5;230m", # light yellow
      error: "\e[38;5;196m" # heavy red
    }.freeze

    # For wrapping string with color codes for prettier inspect.
    # @param [String] str
    #   Content to colorize.
    # @param [Symbol] type
    #   Specify which kind of color to use, valid symbols are defined in {.COLOR_CODE}.
    # @return [String]
    #   String that wrapped with color codes.
    def colorize(str, type)
      return str unless color_enabled?

      cc = COLOR_CODE
      color = cc.key?(type) ? cc[type] : ''
      "#{color}#{str.sub(COLOR_CODE[:esc_m], color)}#{cc[:esc_m]}"
    end

    def color_enabled?
      $stderr.tty?
    end
  end
end
