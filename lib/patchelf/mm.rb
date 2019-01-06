module PatchELF
  # Memory management, provides malloc/free to allocate LOAD segments.
  class MM
    # Instantiate a {MM} object.
    # @param [ELFTools::ELFFile] elf
    def initialize(elf)
      @elf = elf
      @request = []
    end

    def malloc(size, &block)
      @request << [size, block]
    end

    def dispatch!; end
  end
end
