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
      # If nothing is modified, return directly.
      return if out_file.nil? && !dirty?

      out_file ||= @in_file
      # [{Integer => String}]
      @inline_patch = {}
      @mm = PatchELF::MM.new(@elf)
      # Patching interpreter is the easiest.
      patch_interpreter(@set[:interpreter])

      @mm.dispatch!
      FileUtils.cp(@in_file, out_file) if out_file != @in_file

      File.open(out_file, 'r+') do |f|
        @elf.patches.merge(@inline_patch).each do |pos, str|
          f.pos = pos
          f.write(str)
        end
      end

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

      seg_header = @elf.segment_by_type(:interp).header

      patch = proc do |off, vaddr|
        # Register an inline patching
        @inline_patch[off] = new_interp

        # The patching feature of ELFTools
        seg_header.p_offset = off
        seg_header.p_vaddr = seg_header.p_paddr = vaddr
        seg_header.p_filesz = seg_header.p_memsz = new_interp.size

        sec_header = section_header('.interp')
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
  end
end
