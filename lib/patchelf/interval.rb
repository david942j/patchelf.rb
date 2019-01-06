module PatchELF
  # Provides easier-to-use methods for manipulating LOAD segment.
  #
  # Internal use only.
  class Interval
    include Comparable

    attr_reader :head # @return [Integer] Head.
    attr_reader :size # @return [Integer] Length.

    # @param [Integer] head
    # @param [Integer] size
    def initialize(head, size)
      @head = head
      @size = size
    end

    # Comparator.
    # @param [Interval] other
    def <=>(other)
      head <=> other.head
    end

    # @return [Integer]
    #   The end of this interval.
    def tail
      head + size
    end
  end
end
