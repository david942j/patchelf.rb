require 'patchelf/helper'
require 'patchelf/interval'

module PatchELF
  # Memory management, provides malloc/free to allocate LOAD segments.
  class MM
    attr_reader :extend_size # @return [Integer] The size extended.
    attr_reader :threshold # @return [Integer] Where the file start to be extended.

    # Instantiate a {MM} object.
    # @param [ELFTools::ELFFile] elf
    def initialize(elf)
      @elf = elf
      @request = []
    end

    # @param [Integer] size
    # @return [void]
    # @yieldparam [Integer] off
    # @yieldparam [Integer] vaddr
    # @yieldreturn [void]
    #   One can only do the following things in the block:
    #   1. Set ELF headers' attributes (with ELFTools)
    #   2. Invoke {Patcher#inline_patch}
    def malloc(size, &block)
      # TODO: check size > 0
      @request << [size, block]
    end

    # Let the malloc / free requests be effective.
    # @return [void]
    def dispatch!
      return if @request.empty?

      request_size = @request.map(&:first).inject(0, :+)
      # TODO: raise exception if no LOAD exists.

      # We're going to expand the first LOAD segment.
      # Sometimes there's a 'gap' between the first and the second LOAD segment,
      # in this case we only need to expand the first LOAD segment and remain all other things unchanged.
      if gap_useful?(request_size)
        invoke_callbacks
        grow_first_load(request_size)
      elsif extendable?(request_size)
        # After extended we should have large enough 'gap'.

        # |  1  | |  2  |
        # |  1  |        |  2  |
        #=>
        # |  1      | |  2  |
        # |  1      |    |  2  |
        # This is really dangerous..
        # We have to check all p_offset / sh_offset
        # 1. Use ELFTools to patch all headers
        # 2. Mark the extended size, inline_patch will behave different after this.
        # 3. Invoke block.call, which might copy tables and (not-allow-to-patch) strings into the gap

        @threshold = load_segments[1].file_head
        # 1.file_tail + request_size <= 2.file_head + 0x1000x
        @extend_size = PatchELF::Helper.alignup(request_size - gap_between_load.size)
        shift_attributes

        invoke_callbacks
        grow_first_load(request_size)
        # else
        # This can happen in 32bit
      end
    end

    # Query if extended.
    # @return [Boolean]
    def extended?
      defined?(@threshold)
    end

    # Get correct offset after the extension.
    #
    # @param [Integer] off
    # @return [Integer]
    #   Shifted offset.
    def extended_offset(off)
      return off unless defined?(@threshold)
      return off if off < @threshold

      off + @extend_size
    end

    private

    def gap_useful?(need_size)
      # Two conditions:
      # 1. gap is large enough
      gap = gap_between_load
      return false if gap.size < need_size

      # XXX: Do we really need this..?
      # If gap is enough but not all zeros, we will fail on extension..
      # 2. gap is all zeroes.
      # @elf.stream.pos = gap.head
      # return false unless @elf.stream.read(gap.size).bytes.inject(0, :+).zero?

      true
    end

    # @return [PatchELF::Interval]
    def gap_between_load
      # We need this cache since the second LOAD might be changed
      return @gap_between_load if defined?(@gap_between_load)

      loads = load_segments.map do |seg|
        PatchELF::Interval.new(seg.file_head, seg.size)
      end
      # TODO: raise if loads.min != loads.first

      loads.sort!
      # Only one LOAD, the gap has infinity size!
      size = if loads.size == 1 then Float::INFINITY
             else loads[1].head - loads.first.tail
             end
      @gap_between_load = PatchELF::Interval.new(loads.first.tail, size)
    end

    # For all attributes >= threshold, += offset
    def shift_attributes
      # ELFHeader->section_header
      # Sections:
      #   all
      # Segments:
      #   all
      # XXX: will be buggy if one day the number of segments might be changed.

      # Bottom-up
      @elf.each_sections do |sec|
        sec.header.sh_offset += extend_size if sec.header.sh_offset >= threshold
      end
      @elf.each_segments do |seg|
        next unless seg.header.p_offset >= threshold

        seg.header.p_offset += extend_size
        # We have to change align of LOAD segment since ld.so checks it.
        seg.header.p_align = Helper::PAGE_SIZE if seg.is_a?(ELFTools::Segments::LoadSegment)
      end

      @elf.header.e_shoff += extend_size if @elf.header.e_shoff >= threshold
    end

    def load_segments
      @elf.segments_by_type(:load)
    end

    def extendable?(request_size)
      loads = load_segments
      # We can assume loads.size >= 2 because
      # 0: has raised an exception before
      # 1: the gap must be used, nobody cares extendable size.
      # Calcluate the max size of the first LOAD segment can be.
      PatchELF::Helper.aligndown(loads[1].mem_head) - loads.first.mem_tail >= request_size
    end

    def invoke_callbacks
      seg = load_segments.first
      cur = gap_between_load.head
      @request.each do |sz, block|
        block.call(cur, seg.offset_to_vma(cur))
        cur += sz
      end
    end

    def grow_first_load(size)
      seg = load_segments.first
      seg.header.p_filesz += size
      seg.header.p_memsz += size
    end
  end
end
