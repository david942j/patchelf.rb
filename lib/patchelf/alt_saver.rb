# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/elf_file'
require 'elftools/structs'
require 'elftools/util'
require 'patchelf/helper'
require 'fileutils'

module ELFTools
  module Constants
    module PF
      PF_X = 1
      PF_W = 2
      PF_R = 4
    end
    include PF

    module SHN
      SHN_UNDEF     =	0      # undefined section
      SHN_LORESERVE = 0xff00 # start of reserved indices
      SHN_HIRESERVE = 0xffff # end of reserved indices
    end
    include SHN

    module DT
      DT_VERSYM	= 0x6ffffff0
    end
    include DT
  end
end

module PatchELF
  # Internal use only.
  #
  # For {Patcher} to do patching things and save to file.
  # @private
  class AltSaver
    # using ELFTools
    attr_reader :in_file # @return [String] Input filename.
    attr_reader :out_file # @return [String] Output filename.

    # Instantiate a {Saver} object.
    # @param [String] in_file
    # @param [String] out_file
    # @param [{Symbol => String, Array}] set
    def initialize(in_file, out_file, set)
      @in_file = in_file
      @out_file = out_file
      @set = set

      f = File.open(in_file, 'rb+')
      @elf = ELFTools::ELFFile.new(f)
      @buffer = StringIO.new(f.tap(&:rewind).read) # StringIO makes easier to work with Bindata

      @ehdr = @elf.header
      @segments = @elf.segments # usage similar to phdrs
      @sections = @elf.sections # usage similar to shdrs
      update_section_idx!

      # {String => String}
      # section name to its data mapping
      @replaced_sections = {}
      @section_alignment = ehdr.e_phoff.num_bytes
    end

    # @return [void]
    def save!
      @set.each { |mtd, val| send(:"modify_#{mtd}") if val }
      rewrite_sections

      FileUtils.cp(in_file, out_file) if out_file != in_file
      patch_out
      # Let output file have the same permission as input.
      FileUtils.chmod(File.stat(in_file).mode, out_file)
    end

    private

    attr_reader :ehdr

    def buf_cstr(off)
      cstr = []
      with_buf_at(off) do |buf|
        loop do
          c = buf.read 1
          break if c.nil? || c == "\x00"

          cstr.push c
        end
      end
      cstr.join
    end

    def buf_move!(dst_idx, src_idx, n_bytes)
      with_buf_at(src_idx) do |buf|
        to_write = buf.read(n_bytes)
        buf.seek dst_idx
        buf.write to_write
      end
    end

    def dynstr
      find_section '.dynstr'
    end

    # yields dynamic tag, and offset in buffer
    def each_dynamic_tags
      return unless block_given?

      sec = find_section '.dynamic'
      return unless sec

      shdr = sec.header
      with_buf_at(shdr.sh_offset) do |buf|
        dyn = ELFTools::Structs::ELF_Dyn.new(elf_class: shdr.elf_class, endian: shdr.class.self_endian)
        loop do
          buf_dyn_offset = buf.tell
          dyn.clear
          dyn.read(buf)
          break if dyn.d_tag == ELFTools::Constants::DT_NULL

          yield dyn, buf_dyn_offset
          # safety :*
          buf.seek buf_dyn_offset + dyn.num_bytes
        end
      end
    end

    def find_section(sec_name)
      idx = find_section_idx sec_name
      return unless idx

      @sections[idx]
    end

    def find_section_idx(sec_name)
      # @sections.find_index { |s| s.name == sec_name }
      @section_idx_by_name[sec_name]
    end

    def grow_file(newsz)
      bufsz = @buffer.size
      return if newsz <= bufsz

      @buffer.truncate newsz
    end

    def modify_interpreter
      @replaced_sections['.interp'] = @set[:interpreter] + "\x00"
    end

    def modify_needed
      raise NotImplementedError
    end

    def modify_rpath
      modify_rpath_helper @set[:rpath], force_rpath: true
    end

    def modify_runpath
      modify_rpath_helper @set[:runpath]
    end

    def modify_rpath_helper(new_rpath, force_rpath: false)
      return if new_rpath.nil?

      shdr_dynstr = dynstr.header
      strtab_off = shdr_dynstr.sh_offset

      endian = shdr_dynstr.class.self_endian
      elf_class = shdr_dynstr.elf_class

      dyn_rpath = dyn_runpath = nil
      dyn_num_bytes = nil
      dt_null_idx = 0
      rpath_off = nil
      dyn_buf_off = {}

      each_dynamic_tags do |dyn, off|
        case dyn.d_tag
        when ELFTools::Constants::DT_RPATH
          dyn_buf_off[:rpath] = off
          # clone does shallow copy, and for some reason d_tag and d_val can't be pass as argument
          dyn_rpath = ELFTools::Structs::ELF_Dyn.new(endian: endian, elf_class: elf_class)
          dyn_rpath.d_tag = dyn.d_tag.to_i
          dyn_rpath.d_val = dyn.d_val.to_i
          rpath_off = strtab_off + dyn.d_val if dyn_runpath.nil?
        when ELFTools::Constants::DT_RUNPATH
          dyn_buf_off[:runpath] = off
          dyn_runpath = ELFTools::Structs::ELF_Dyn.new(endian: endian, elf_class: elf_class)
          dyn_runpath.d_tag = dyn.d_tag.to_i
          dyn_runpath.d_val = dyn.d_val.to_i
          rpath_off = strtab_off + dyn.d_val
        end
        dyn_num_bytes ||= dyn.num_bytes
        dt_null_idx += 1
      end
      old_rpath = rpath_off ? buf_cstr(rpath_off) : ''

      modified_d_tag = nil
      if !force_rpath && dyn_rpath && dyn_runpath.nil?
        dyn_rpath.d_tag = ELFTools::Constants::DT_RUNPATH
        dyn_runpath = dyn_rpath
        dyn_rpath = nil
        dyn_buf_off[:runpath] = dyn_buf_off[:rpath]
        dyn_buf_off.delete :rpath

        modified_d_tag = :runpath
      elsif force_rpath && dyn_runpath
        dyn_runpath.d_tag = ELFTools::Constants::DT_RPATH
        dyn_rpath = dyn_runpath
        dyn_runpath = nil
        dyn_buf_off[:rpath] = dyn_buf_off[:runpath]
        dyn_buf_off.delete :runpath

        modified_d_tag = :rpath
      end

      if old_rpath == new_rpath
        if modified_d_tag
          dyn_offset = dyn_buf_off[modified_d_tag]
          dyn = dyn_runpath || dyn_rpath # ugh!
          with_buf_at(dyn_offset) { |buf| dyn.write(buf) }
        end

        return
      end

      with_buf_at(rpath_off) { |b| b.write('X' * old_rpath.size) } if rpath_off

      if new_rpath.size <= old_rpath.size
        with_buf_at(rpath_off) { |b| b.write "#{new_rpath}\x00" }
        return
      end

      # PatchELF::Logger.info 'rpath is too long, resizing...'
      new_dynstr = replace_section '.dynstr', shdr_dynstr.sh_size + new_rpath.size + 1
      new_rpath_strtab_idx = shdr_dynstr.sh_size.to_i
      new_dynstr[new_rpath_strtab_idx..(new_rpath_strtab_idx + new_rpath.size)] = "#{new_rpath}\x00"

      if dyn_runpath
        dyn_runpath.d_val = new_rpath_strtab_idx
        with_buf_at(dyn_buf_off[:runpath]) { |b| dyn_runpath.write(b) }
      end

      if dyn_rpath
        dyn_rpath.d_val = new_rpath_strtab_idx
        with_buf_at(dyn_buf_off[:rpath]) { |b| dyn_rpath.write(b) }
      end
      return if dyn_rpath || dyn_runpath

      # allot for new dt_runpath
      shdr_dynamic = find_section('.dynamic').header
      new_dynamic_data = replace_section '.dynamic', shdr_dynamic.sh_size + dyn_num_bytes

      # consider DT_NULL when copying
      replacement_size = (dt_null_idx + 1) * dyn_num_bytes

      # make space for dt_runpath tag at the top, shift data by one tag positon
      new_dynamic_data[dyn_num_bytes..(replacement_size + dyn_num_bytes)] = new_dynamic_data[0..replacement_size]

      dyn_rpath = ELFTools::Structs::ELF_Dyn.new endian: endian, elf_class: elf_class
      dyn_rpath.d_tag = force_rpath ? ELFTools::Constants::DT_RPATH : ELFTools::Constants::DT_RUNPATH
      dyn_rpath.d_val = new_rpath_strtab_idx

      zi = StringIO.new
      dyn_rpath.write zi
      zi.rewind
      new_dynamic_data[0..dyn_num_bytes] = zi.read
    end

    def modify_soname
      return unless ehdr.e_type == ELFTools::Constants::ET_DYN

      raise NotImplementedError
    end

    def normalize_note_segments!
      sht_note = ELFTools::Constants::SHT_NOTE
      return if @replaced_sections.none? { |sec_name, _| find_section(sec_name).header.sh_type == sht_note }

      endian = elf_class = nil
      @sections.first.header.tap do |shdr|
        endian = shdr.class.self_endian
        elf_class = shdr.elf_class
      end

      # new segments maybe be added as we iterate
      (1...@segments.count).each do |idx|
        seg = @segments[idx]
        phdr = seg.header

        next if phdr.p_type != ELFTools::Constants::PT_NOTE

        start_off = phdr.p_offset
        curr_off = start_off
        end_off = phdr.p_offset + phdr.p_filesz

        while curr_off < end_off
          note_sec = @sections.find { |s| s.header.sh_type == sht_note && s.header.sh_offset == curr_off }
          if note_sec.nil?
            raise PatchELF::PatchError, 'cannot normalize PT_NOTE segment: non-contiguous SHT_NOTE sections'
          end

          size = note_sec.header.sh_size
          if curr_off + size > end_off
            raise PatchELF::PatchError, 'cannot normalize PT_NOTE segment: partially mapped SHT_NOTE section.'
          end

          new_phdr = ELFTools::Structs::ELF_Phdr[elf_class].new(
            endian: endian,
            p_type: phdr.p_type,
            p_offset: curr_off,
            p_vaddr: phdr.p_vaddr + (curr_off - start_off),
            p_paddr: phdr.p_paddr + (curr_off - start_off),
            p_filesz: size,
            p_memsz: size,
            p_flags: phdr.p_flags,
            p_align: phdr.p_align
          )

          new_segment = ELFTools::Segments::Segment.new(new_phdr, nil)

          if curr_off == start_off
            @segments[idx] = new_segment
          else
            @segments.push new_segment
          end

          curr_off += size
        end
      end
      ehdr.e_phnum = @segments.count
    end

    def page_size
      Helper::PAGE_SIZE
    end

    def patch_out
      with_buf_at(0) { |b| ehdr.write(b) }

      File.open(out_file, 'wb+') do |f|
        @buffer.rewind
        f.write @buffer.read
      end
    end

    # size includes NUL byte
    def replace_section(section_name, size)
      data = @replaced_sections[section_name]
      unless data
        shdr = find_section(section_name).header
        with_buf_at(shdr.sh_offset) { |b| data = b.read shdr.sh_size }
      end
      rep_data = if data.size == size
                   data
                 elsif data.size < size
                   data.ljust(size, "\x00")
                 else
                   data[0...size] + "\x00"
                 end
      @replaced_sections[section_name] = rep_data
    end

    def rewrite_headers(phdr_address)
      # there can only be a single program header table according to ELF spec
      @segments.find { |seg| seg.header.p_type == ELFTools::Constants::PT_PHDR }&.tap do |seg|
        phdr = seg.header
        phdr.p_offset = ehdr.e_phoff.to_i
        phdr.p_vaddr = phdr.p_paddr = phdr_address.to_i
        phdr.p_filesz = phdr.p_memsz = phdr.num_bytes * @segments.count # e_phentsize * e_phnum
      end

      sort_phdrs!
      with_buf_at(ehdr.e_phoff) do |buf|
        @segments.each { |seg| seg.header.write(buf) }
      end
      raise PatchELF::PatchError, 'ehdr.e_shnum /= @sections.count' unless ehdr.e_shnum == @sections.count

      sort_shdrs!
      with_buf_at(ehdr.e_shoff) do |buf|
        @sections.each { |section| section.header.write(buf) }
      end

      each_dynamic_tags do |dyn, buf_off|
        case dyn.d_tag
        when ELFTools::Constants::DT_STRTAB
          dyn.d_val = dynstr.header.sh_addr.to_i
        when ELFTools::Constants::DT_STRSZ
          dyn.d_val = dynstr.header.sh_size.to_i
        when ELFTools::Constants::DT_SYMTAB
          dyn.d_val = find_section('.dynsym').header.sh_addr.to_i
        when ELFTools::Constants::DT_HASH
          dyn.d_val = find_section('.hash').header.sh_addr.to_i
        when ELFTools::Constants::DT_GNU_HASH
          dyn.d_val = find_section('.gnu.hash').header.sh_addr.to_i
        when ELFTools::Constants::DT_JMPREL
          shdr = @sections.find { |s| %w[.rel.plt .rela.plt .rela.IA_64.pltoff].include? s.name }&.header
          raise PatchELF::PatchError, 'cannot find section corresponding to DT_JMPREL' if shdr.nil?

          dyn.d_val = shdr.sh_addr.to_i
        when ELFTools::Constants::DT_REL
          # regarding .rel.got, NixOS/patchelf says
          # "no idea if this makes sense, but it was needed for some program"
          shdr = @sections.find { |s| %w[.rel.dyn .rel.got].include? s.name }&.header
          next if shdr.nil? # patchelf claims no problem in skipping

          dyn.d_val = shdr.sh_addr.to_i
        when ELFTools::Constants::DT_RELA
          shdr = find_section('.rela.dyn')&.header
          next if shdr.nil? # patchelf claims no problem in skipping

          dyn.d_val = shdr.sh_addr.to_i
        when ELFTools::Constants::DT_VERNEED
          dyn.d_val = find_section('.gnu.version_r').header.sh_addr.to_i
        when ELFTools::Constants::DT_VERSYM
          dyn.d_val = find_section('.gnu.version').header.sh_addr.to_i
        else
          next
        end

        with_buf_at(buf_off) { |wbuf| dyn.write(wbuf) }
      end

      old_sections = @elf.sections
      symtabs = [ELFTools::Constants::SHT_SYMTAB, ELFTools::Constants::SHT_DYNSYM]

      endian = ehdr.class.self_endian

      # resort to manual packing and unpacking of data,
      # as using bindata is painfully slow :(
      if ehdr.elf_class == 32
        sym_num_bytes = 16 # u32 u32 u32 u8 u8 u16
        pack_code = endian == :little ? 'VVVCCv' : 'NNNCCn'
        pack_st_info = 3
        pack_st_shndx = 5
        pack_st_value = 1
      else # 64
        sym_num_bytes = 24 # u32 u8 u8 u16 u64 u64
        pack_code = endian == :little ? 'VCCvQ<Q<' : 'NCCnQ>Q>'
        pack_st_info = 1
        pack_st_shndx = 3
        pack_st_value = 4
      end

      @sections.each do |sec|
        shdr = sec.header
        next unless symtabs.include?(shdr.sh_type)

        with_buf_at(shdr.sh_offset) do |buf|
          num_symbols = shdr.sh_size / sym_num_bytes
          num_symbols.times do |entry|
            sym = buf.read(sym_num_bytes).unpack(pack_code)
            shndx = sym[pack_st_shndx]

            next if shndx == ELFTools::Constants::SHN_UNDEF || shndx >= ELFTools::Constants::SHN_LORESERVE

            if shndx >= old_sections.count
              PatchELF::Logger.warn "entry #{entry} in symbol table refers to a non existing section, skipping"
              next
            end

            old_sec = old_sections[shndx]
            raise PatchELF::PatchError, '@elf.sections[shndx] is nil' if old_sec.nil?

            new_index = find_section_idx old_sec.name
            sym[pack_st_shndx] = new_index

            # right 4 bits in the st_info field is st_type
            if (sym[pack_st_info] & 0xF) == ELFTools::Constants::STT_SECTION
              sym[pack_st_value] = @sections[new_index].header.sh_addr.to_i
            end

            buf.seek buf.tell - sym_num_bytes
            buf.write sym.pack(pack_code)
          end
        end
      end
    end

    def rewrite_sections
      return if @replaced_sections.empty?

      case ehdr.e_type
      when ELFTools::Constants::ET_DYN
        rewrite_sections_library
      when ELFTools::Constants::ET_EXEC
        rewrite_sections_executable
      else
        raise PatchELF::PatchError, 'unknown ELF type'
      end
    end

    def rewrite_sections_executable
      seg_num_bytes = @segments.first.header.num_bytes
      sort_shdrs!

      last_replaced = 0
      @sections.each_with_index { |sec, idx| last_replaced = idx if @replaced_sections[sec.name] }

      raise PatchELF::PatchError, 'last_replaced = 0' if last_replaced.zero?
      raise PatchELF::PatchError, 'last_replaced + 1 >= @sections.size' if last_replaced + 1 >= @sections.size

      # PatchELF::Logger.info "last replaced = #{last_replaced}"

      start_replacement_hdr = @sections[last_replaced + 1].header
      start_offset = start_replacement_hdr.sh_offset
      start_addr = start_replacement_hdr.sh_addr

      prev_sec_name = ''
      (1..last_replaced).each do |idx|
        sec = @sections[idx]
        shdr = sec.header
        if (sec.type == ELFTools::Constants::SHT_PROGBITS && sec.name != '.interp') || prev_sec_name == '.dynstr'
          start_addr = shdr.sh_addr
          start_offset = shdr.sh_offset
          last_replaced = idx - 1
          break
        elsif @replaced_sections[sec.name].nil?
          # PatchELF::Logger.info " replacing section #{sec.name} which is in the way"
          # get blocking section out of the way
          replace_section(sec.name, shdr.sh_size)
        end

        prev_sec_name = sec.name
      end

      # PatchELF::Logger.info "first reserved offset/addr is 0x#{start_offset.to_i.to_s 16}/0x#{start_addr.to_i.to_s 16}"

      unless start_addr % page_size == start_offset % page_size
        raise PatchELF::PatchError, 'start_addr /= start_offset (mod PAGE_SIZE)'
      end

      first_page = start_addr - start_offset
      # PatchELF::Logger.info "first page is 0x#{first_page.to_i.to_s 16}"

      if ehdr.e_shoff < start_offset
        shoff_new = @buffer.size
        sh_size = ehdr.e_shoff + ehdr.e_shnum * ehdr.e_shentsize
        grow_file @buffer.size + sh_size
        ehdr.e_shoff = shoff_new
        raise PatchELF::PatchError, 'ehdr.e_shnum /= @sections.size' unless ehdr.e_shnum == @sections.size

        with_buf_at(ehdr.e_shoff + @sections.first.header.num_bytes) do |buf| # skip writing to NULL section
          @sections.each_with_index do |sec, idx|
            next if idx.zero?

            sec.header.write buf
          end
        end
      end

      normalize_note_segments!

      needed_space = (
        ehdr.num_bytes +
        (@segments.count * seg_num_bytes) +
        @replaced_sections.sum { |_, str| Helper.alignup(str.size, @section_alignment) }
      )

      # PatchELF::Logger.info "needed space is #{needed_space}"

      if needed_space > start_offset
        needed_space += seg_num_bytes # new load segment is required
        # PatchELF::Logger.info "needed space is #{needed_space}"

        needed_pages = Helper.alignup(needed_space - start_offset, page_size) / page_size
        # PatchELF::Logger.info "needed pages is #{needed_pages}"
        raise PatchELF::PatchError, 'virtual address space underrun' if needed_pages * page_size > first_page

        first_page -= needed_pages * page_size
        start_offset += needed_pages * page_size

        shift_file(needed_pages, first_page)
      end

      # PatchELF::Logger.info "needed space is #{needed_space}"

      cur_off = ehdr.num_bytes + (@segments.count * seg_num_bytes)
      # PatchELF::Logger.info "clearing first #{start_offset - cur_off} bytes"

      with_buf_at(cur_off) { |buf| buf.write "\x00" * (start_offset - cur_off) }
      cur_off = write_replaced_sections cur_off, first_page, 0
      # PatchELF::Logger.info " cur_off = #{cur_off} "
      raise PatchELF::PatchError, 'cur_off /= needed_space' if cur_off != needed_space

      rewrite_headers first_page + ehdr.e_phoff
    end

    def rewrite_sections_library
      start_page =
        @segments.map { |seg| Helper.alignup(seg.header.p_vaddr + seg.header.p_memsz, page_size) }
                 .max

      # PatchELF::Logger.info "Last page is 0x#{start_page.to_s 16}"
      num_notes = @sections.count { |sec| sec.header.sh_type == ELFTools::Constants::SHT_NOTE }
      pht_size = ehdr.num_bytes + (@segments.count + 1 + num_notes) * @segments.first.header.num_bytes
      # replace sections that may overlap with expanded program header table
      @sections.each_with_index do |sec, idx|
        shdr = sec.header
        next if idx.zero? || @replaced_sections[sec.name]
        break if shdr.sh_addr > pht_size

        replace_section sec.name, shdr.sh_size
      end

      needed_space = @replaced_sections.sum { |_, str| Helper.alignup(str.size, @section_alignment) }
      # PatchELF::Logger.info "needed space = #{needed_space}"

      start_offset = Helper.alignup(@buffer.size, page_size)
      grow_file start_offset + needed_space

      # executable shared object
      if start_offset > start_page && @segments.any? { |seg| seg.header.p_type == ELFTools::Constants::PT_INTERP }
        #   PatchELF::Logger.info(
        #     "shifting new PT_LOAD segment by #{start_offset - start_page} bytes to work around a Linux kernel bug"
        #   )
        start_page = start_offset
      end

      ehdr.e_phnum += 1
      ehdr.e_phoff = ehdr.num_bytes
      phdr = ELFTools::Structs::ELF_Phdr[@elf.elf_class].new(
        endian: @elf.endian,
        p_type: ELFTools::Constants::PT_LOAD,
        p_offset: start_offset,
        p_vaddr: start_page,
        p_paddr: start_page,
        p_filesz: needed_space,
        p_memsz: needed_space,
        p_flags: ELFTools::Constants::PF_R | ELFTools::Constants::PF_W,
        p_align: page_size
      )
      # no stream
      @segments.push ELFTools::Segments::Segment.new(phdr, nil)

      normalize_note_segments!

      cur_off = write_replaced_sections start_offset, start_page, start_offset
      raise PatchELF::PatchError, 'cur_off /= start_offset+needed_space' if cur_off != start_offset + needed_space

      rewrite_headers ehdr.e_phoff
    end

    def shift_file(extra_pages, start_page)
      oldsz = @buffer.size
      shift = extra_pages * page_size
      grow_file(oldsz + shift)

      buf_move! shift, 0, oldsz
      with_buf_at(ehdr.num_bytes) { |buf| buf.write "\x00" * (shift - ehdr.num_bytes) }

      ehdr.e_phoff = ehdr.num_bytes
      ehdr.e_shoff = ehdr.e_shoff + shift

      @sections.each_with_index do |sec, i|
        next if i.zero? # dont touch NULL section

        shdr = sec.header
        shdr.sh_offset += shift
      end

      @segments.each do |seg|
        phdr = seg.header
        phdr.p_offset += shift
        phdr.p_align = page_size if phdr.p_align != 0 && (phdr.p_vaddr - phdr.p_offset) % phdr.p_align != 0
      end

      ehdr.e_phnum += 1
      phdr = ELFTools::Structs::ELF_Phdr[@elf.elf_class].new(
        endian: @elf.endian,
        p_type: ELFTools::Constants::PT_LOAD,
        p_offset: 0,
        p_vaddr: start_page,
        p_paddr: start_page,
        p_filesz: shift,
        p_memsz: shift,
        p_flags: ELFTools::Constants::PF_R | ELFTools::Constants::PF_W,
        p_align: page_size
      )
      # no stream
      @segments.push ELFTools::Segments::Segment.new(phdr, nil)
    end

    def sort_phdrs!
      pt_phdr = ELFTools::Constants::PT_PHDR
      @segments.sort! do |me, you|
        next  1 if you.header.p_type == pt_phdr
        next -1 if me.header.p_type == pt_phdr

        me.header.p_paddr.to_i <=> you.header.p_paddr.to_i
      end
    end

    def sort_shdrs!
      rel_syms = [ELFTools::Constants::SHT_REL, ELFTools::Constants::SHT_RELA]

      # Translate sh_link mappings to section names, since sorting the
      # sections will invalidate the sh_link fields.
      # similar for sh_info
      linkage, info = @sections.each_with_object([{}, {}]) do |s, (link, info)|
        hdr = s.header
        link[s.name] = @sections[hdr.sh_link].name if hdr.sh_link.nonzero?
        info[s.name] = @sections[hdr.sh_info].name if hdr.sh_info.nonzero? && rel_syms.include?(hdr.sh_type)
      end
      shstrtab_name = @sections[ehdr.e_shstrndx].name

      @sections.sort! { |me, you| me.header.sh_offset.to_i <=> you.header.sh_offset.to_i }
      update_section_idx!

      # restore sh_info, sh_link
      @sections.each do |sec|
        hdr = sec.header
        hdr.sh_link = find_section_idx(linkage[sec.name]) if hdr.sh_link.nonzero?
        hdr.sh_info = find_section_idx info[sec.name] if hdr.sh_info.nonzero? && rel_syms.include?(hdr.sh_type)
      end

      ehdr.e_shstrndx = find_section_idx shstrtab_name
    end

    def update_section_idx!
      @section_idx_by_name = @sections.map.with_index { |sec, idx| [sec.name, idx] }.to_h
    end

    def with_buf_at(pos)
      return unless block_given?

      opos = @buffer.tell
      @buffer.seek pos
      yield @buffer
      @buffer.seek opos
      nil
    end

    def write_replaced_sections(cur_off, start_addr, start_offset)
      sht_note = ELFTools::Constants::SHT_NOTE
      sht_no_bits = ELFTools::Constants::SHT_NOBITS
      pt_interp = ELFTools::Constants::PT_INTERP
      pt_dynamic = ELFTools::Constants::PT_DYNAMIC
      pt_note = ELFTools::Constants::PT_NOTE

      # the original source says this has to be done seperately to
      # prevent clobbering the previously written section contents.
      @replaced_sections.each do |rsec_name, _|
        shdr = find_section(rsec_name).header
        with_buf_at(shdr.sh_offset) { |b| b.write('X' * shdr.sh_size) } if shdr.sh_type != sht_no_bits
      end

      noted_segments = Set.new
      # the sort is necessary, the strategy in ruby and Cpp to iterate map/hash
      # is different, patchelf v0.10 iterates the replaced_sections sorted by
      # keys.
      @replaced_sections.sort.each do |rsec_name, rsec_data|
        shdr = find_section(rsec_name).header
        orig_shdr = shdr.new(**shdr.snapshot) # hack! (probably) doesn't work for updating

        # PatchELF::Logger.info "rewriting section '#{rsec_name}' from offset 0x#{shdr.sh_offset.to_i.to_s 16}(size #{shdr.sh_size}) to offset 0x#{cur_off.to_i.to_s 16}(size #{rsec_data.size})"
        with_buf_at(cur_off) { |b| b.write rsec_data }

        shdr.sh_offset = cur_off
        shdr.sh_addr = start_addr + (cur_off - start_offset)
        shdr.sh_size = rsec_data.size
        shdr.sh_addralign = @section_alignment

        if ['.interp', '.dynamic'].include? rsec_name
          seg_type = rsec_name == '.interp' ? pt_interp : pt_dynamic
          @segments.each do |seg|
            next unless (phdr = seg.header).p_type == seg_type

            phdr.p_offset = shdr.sh_offset.to_i
            phdr.p_vaddr = phdr.p_paddr = shdr.sh_addr.to_i
            phdr.p_filesz = phdr.p_memsz = shdr.sh_size.to_i
          end
        end

        if shdr.sh_type == sht_note
          shdr.sh_addralign = orig_shdr.sh_addralign.to_i if orig_shdr.sh_addralign < @section_alignment

          @segments.each_with_index do |seg, seg_idx|
            next if (phdr = seg.header).p_type != pt_note || noted_segments.member?(seg_idx)

            sec_range = (orig_shdr.sh_offset.to_i)...(orig_shdr.sh_offset + orig_shdr.sh_size)
            seg_range = (phdr.p_offset.to_i)...(phdr.p_offset + phdr.p_filesz)

            next unless seg_range.cover?(sec_range.first) || seg_range.cover?(*sec_range.last(1))

            raise PatchELF::PatchError, 'unsupported overlap of SHT_NOTE and PT_NOTE' if seg_range != sec_range

            noted_segments.add(seg_idx)
            phdr.p_offset = shdr.sh_offset.to_i
            phdr.p_paddr = phdr.p_vaddr = shdr.sh_addr.to_i
            phdr.p_filesz = phdr.p_memsz = shdr.sh_size.to_i
          end
        end

        cur_off += Helper.alignup(rsec_data.size, @section_alignment)
      end
      @replaced_sections.clear

      cur_off
    end
  end
end
