# encoding: ascii-8bit
# frozen_string_literal: true

require 'elftools/exceptions'

module PatchELF
  # Raised on an error during ELF modification.
  class PatchError < ELFTools::ELFError; end
end
