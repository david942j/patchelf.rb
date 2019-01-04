require 'elftools'

require 'patchelf/logger'

module PatchELF
  # Class to handle all patching things.
  class Patcher
    def initialize(filename)
      @elf = ELFTools::ELFFile.new(File.open(filename))
    end

    # @param [:interpreter, :needed, :soname] name
    # @return [String, Array, nil]
    def print(name)
      case name
      when :interpreter then interp_name
      when :soname then soname
      when :needed then needed
      end
    end

    private

    def interp_name
      segment = @elf.segment_by_type(:interp)
      return PatchELF::Logger.warn('No interpreter found.') if segment.nil?

      segment.interp_name
    end

    def soname
      segment = dynamic_or_log
      return if segment.nil?

      tag = segment.tag_by_type(:soname)
      return PatchELF::Logger.warn('No soname, not a shared library?') if tag.nil?

      tag.name
    end

    def needed
      segment = dynamic_or_log
      return if segment.nil?

      segment.tags_by_type(:needed).map(&:name)
    end

    def dynamic_or_log
      @elf.segment_by_type(:dynamic).tap do |s|
        PatchELF::Logger.warn('No DYNAMIC segment, might be a statically-linked ELF?') if s.nil?
      end
    end
  end
end
