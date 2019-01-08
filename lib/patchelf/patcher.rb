# encoding: ascii-8bit

require 'elftools'
require 'fileutils'

require 'patchelf/logger'
require 'patchelf/mm'

module PatchELF
  # Class to handle all patching things.
  class Patcher
    # @!macro [new] note_apply
    #   @note This setting will be saved after {#save} being invoked.

    # Instantiate a {Patcher} object.
    # @param [String] filename
    #   Filename of input ELF.
    def initialize(filename)
      @in_file = filename
      @elf = ELFTools::ELFFile.new(File.open(filename))
      @set = {}
    end

    # Set interpreter's name.
    #
    # If the input ELF has no existent interpreter,
    # this method will show a warning and has no effect.
    # @param [String] interp
    # @macro note_apply
    def interpreter=(interp)
      return if interpreter.nil? # will also show warning if there's no interp segment.

      @set[:interpreter] = interp
    end

    # Set soname.
    #
    # If the input ELF is not a shared library with a soname,
    # this method will show a warning and has no effect.
    # @param [String] name
    # @macro note_apply
    def soname=(name)
      return if soname.nil?

      @set[:soname] = name
    end

    # Set rpath.
    #
    # If DT_RPATH is not presented in the input ELF,
    # a new DT_RPATH attribute will be inserted into the DYNAMIC segment.
    # @param [String] rpath
    # @macro note_apply
    def rpath=(rpath)
      @set[:rpath] = rpath
    end

    # Save the patched ELF as +out_file+.
    # @param [String?] out_file
    #   If +out_file+ is +nil+, the original input file will be modified.
    # @return [void]
    def save(out_file = nil)
      # TODO: Test if we can save twice, and the output files are exactly same.
      # If nothing is modified, return directly.
      return if out_file.nil? && !dirty?

      out_file ||= @in_file
      # [{Integer => String}]
      @inline_patch = {}
      @mm = PatchELF::MM.new(@elf)
      # Patching interpreter is the easiest.
      patch_interpreter(@set[:interpreter])
      patch_dynamic

      @mm.dispatch!

      FileUtils.cp(@in_file, out_file) if out_file != @in_file
      patch_out(out_file)
      # Let output file have the same permission as input.
      FileUtils.chmod(File.stat(@in_file).mode, out_file)
    end

    # Get name(s) of interpreter, needed libraries, rpath, or soname.
    #
    # @param [:interpreter, :needed, :rpath, :soname] name
    # @return [String, Array<String>, nil]
    #   Returns name(s) fetched from ELF.
    # @example
    #   patcher = Patcher.new('/bin/ls')
    #   patcher.get(:interpreter)
    #   #=> "/lib64/ld-linux-x86-64.so.2"
    #   patcher.get(:needed)
    #   #=> ["libselinux.so.1", "libc.so.6"]
    #
    #   patcher.get(:soname)
    #   # [WARN] Entry DT_SONAME not found, not a shared library?
    #   #=> nil
    # @example
    #   Patcher.new('/lib/x86_64-linux-gnu/libc.so.6').get(:soname)
    #   #=> "libc.so.6"
    def get(name)
      return unless %i[interpreter needed rpath soname].include?(name)
      return @set[name] if @set[name]

      __send__(name)
    end

    private

    # @return [String?]
    #   Get interpreter's name.
    # @example
    #   Patcher.new('/bin/ls').interpreter
    #   #=> "/lib64/ld-linux-x86-64.so.2"
    def interpreter
      segment = @elf.segment_by_type(:interp)
      return PatchELF::Logger.warn('No interpreter found.') if segment.nil?

      segment.interp_name
    end

    # @return [Array<String>]
    def needed
      segment = dynamic_or_log
      return if segment.nil?

      segment.tags_by_type(:needed).map(&:name)
    end

    # @return [String?]
    def rpath
      # TODO: consider both rpath and runpath
      tag_name_or_log(:rpath, 'Entry DT_RPATH not found.')
    end

    # @return [String?]
    def soname
      tag_name_or_log(:soname, 'Entry DT_SONAME not found, not a shared library?')
    end

    def patch_interpreter(new_interp)
      return if new_interp.nil?

      new_interp += "\x00"
      old_interp = interpreter + "\x00"
      return if old_interp == new_interp

      # These headers must be found here but not in the proc.
      seg_header = @elf.segment_by_type(:interp).header
      sec_header = section_header('.interp')

      patch = proc do |off, vaddr|
        # Register an inline patching
        inline_patch(off, new_interp)

        # The patching feature of ELFTools
        seg_header.p_offset = off
        seg_header.p_vaddr = seg_header.p_paddr = vaddr
        seg_header.p_filesz = seg_header.p_memsz = new_interp.size

        if sec_header
          sec_header.sh_offset = off
          sec_header.sh_size = new_interp.size
        end
      end

      if new_interp.size <= old_interp.size
        # easy case
        patch.call(seg_header.p_offset.to_i, seg_header.p_vaddr.to_i)
      else
        # hard case, we have to request a new LOAD area
        @mm.malloc(new_interp.size, &patch)
      end
    end

    def patch_dynamic
      # We never do inline patching on strtab's string.
      # 1. Search if there's useful string exists
      #   - only need header patching
      # 2. Append a new string to the strtab.
      #   - register strtab extension
      return if @set[:soname].nil?

      dynamic_or_log.tags # HACK, force @tags to be defined
      # The tag must exist.
      so_tag = dynamic_or_log.tag_by_type(:soname)
      reg_str_table(@set[:soname]) do |idx|
        so_tag.header.d_val = idx
      end
      malloc_strtab!
    end

    def malloc_strtab!
      return unless defined?(@strtab_extend_requests)

      strtab = dynamic_or_log.tag_by_type(:strtab)
      # Process registered requests
      need_size = strtab_string.size + @strtab_extend_requests.reduce(0) { |sum, (str, _)| sum + str.size + 1 }
      dynstr = section_header('.dynstr')
      @mm.malloc(need_size) do |off, vaddr|
        new_str = strtab_string + @strtab_extend_requests.map(&:first).join("\x00") + "\x00"
        inline_patch(off, new_str)
        @strtab_extend_requests.each do |str, block|
          # TODO: make here more efficient
          block.call(new_str.index(str + "\x00"))
        end
        # Now patching strtab header
        strtab.header.d_val = vaddr
        # We also need to patch dynstr to let readelf have correct output.
        if dynstr
          dynstr.sh_size = new_str.size
          dynstr.sh_offset = off
          dynstr.sh_addr = vaddr
        end
      end
    end

    # @param [String]
    # @yieldparam [Integer] idx
    # @yieldreturn [void]
    def reg_str_table(str, &block)
      idx = strtab_string.index(str + "\x00")
      # Request string is already exist
      return yield idx if idx

      # Record the request
      @strtab_extend_requests ||= []
      @strtab_extend_requests << [str, block]
    end

    def strtab_string
      return @strtab_string if defined?(@strtab_string)

      # TODO: handle no strtab exists..
      offset = @elf.offset_from_vma(dynamic_or_log.tag_by_type(:strtab).value)
      # This is a little tricky since no length information is stored in the tag.
      # We first get the file offset of the string then 'guess' where the end is.
      @elf.stream.pos = offset
      @strtab_string = ''
      loop do
        c = @elf.stream.read(1)
        break unless c =~ /\x00|[[:print:]]/

        @strtab_string << c
      end
      @strtab_string
    end

    # @return [Boolean]
    def dirty?
      @set.any?
    end

    # @return [ELFTools::Sections::Section?]
    def section_header(name)
      sec = @elf.section_by_name(name)
      return if sec.nil?

      sec.header
    end

    def tag_name_or_log(type, log_msg)
      segment = dynamic_or_log
      return if segment.nil?

      tag = segment.tag_by_type(type)
      return PatchELF::Logger.warn(log_msg) if tag.nil?

      tag.name
    end

    def dynamic_or_log
      @elf.segment_by_type(:dynamic).tap do |s|
        PatchELF::Logger.warn('DYNAMIC segment not found, might be a statically-linked ELF?') if s.nil?
      end
    end

    # This can only be used for patching interpreter's name
    # or set strings in a malloc-ed area.
    # i.e. NEVER intend to change the string defined in strtab
    def inline_patch(off, str)
      @inline_patch[@mm.extended_offset(off)] = str
    end

    # Modify the out_file according to registered patches.
    def patch_out(out_file)
      # if @mm.extend_size != 0:
      # 1. Remember all data after the original second LOAD
      # 2. Apply patches before the second LOAD.
      # 3. Apply patches located after the second LOAD.

      File.open(out_file, 'r+') do |f|
        if @mm.extended?
          original_head = @mm.threshold
          extra = {}
          # Copy all data after the second load
          @elf.stream.pos = original_head
          extra[original_head + @mm.extend_size] = @elf.stream.read # read to end
          # zero out the 'gap' we created
          extra[original_head] = "\x00" * @mm.extend_size
          extra.each do |pos, str|
            f.pos = pos
            f.write(str)
          end
        end
        @elf.patches.each do |pos, str|
          f.pos = @mm.extended_offset(pos)
          f.write(str)
        end

        @inline_patch.each do |pos, str|
          f.pos = pos
          f.write(str)
        end
      end
    end
  end
end
