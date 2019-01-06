require 'patchelf/helper'
require 'patchelf/interval'

module PatchELF
  # Memory management, provides malloc/free to allocate LOAD segments.
  class MM
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
    def malloc(size, &block)
      # TODO: check size > 0
      @request << [size, block]
    end

    # Let the malloc / free requests be effective.
    # @return [void]
    def dispatch!
      return if @request.empty?

      request_size = @request.map(&:first).sum
      # TODO: raise exception if no LOAD exists.

      # We're going to expand the first LOAD segment.
      # Sometimes there's a 'gap' between the first and the second LOAD segment,
      # in this case we only need to expand the first LOAD segment and remain all other things unchanged.
      if gap_useful?(request_size)
        seg = @elf.segment_by_type(:load)
        cur = gap_between_load.head
        @request.each do |sz, block|
          block.call(cur, seg.offset_to_vma(cur))
          cur += sz
        end
        seg.header.p_filesz += request_size
        seg.header.p_memsz += request_size
      elsif extendable_size >= request_size
        # else
      end
    end

    private

    def gap_useful?(need_size)
      # Two conditions:
      # 1. gap is large enough
      # 2. gap is all zeroes.
      gap = gap_between_load
      return false if gap.size < need_size

      # check gap is all zeroes
      @elf.stream.pos = gap.head
      return false unless @elf.stream.read(gap.size).bytes.sum.zero?

      true
    end

    # @return [PatchELF::Interval]
    def gap_between_load
      return @gap_between_load if defined?(@gap_between_load)

      loads = @elf.segments_by_type(:load).map do |seg|
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

    # Calcluate the max size of the first LOAD segment can be.
    def extendable_size
      loads = @elf.segments_by_type(:load)
      # We can assume loads.size >= 2 because
      # 0: has raised an exception before
      # 1: the gap must be used, nobody cares extendable size.
      PatchELF::Helper.aligndown(loads[1].mem_head) - loads.first.mem_tail
    end
  end
end
