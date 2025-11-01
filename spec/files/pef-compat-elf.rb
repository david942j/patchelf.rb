#!/usr/bin/env ruby
# frozen_string_literal: true

require 'elftools'
OUT_ELF = ARGV.first || 'pef-compat.elf'

# pollute
include ELFTools::Constants
include ELFTools::Structs

PAGE_SIZE = 4096
START_ADDR = 0x4000 # chosen without any reason
Phdr = ELF64_Phdr
Shdr = ELF_Shdr
section_alignment = 8

def aligndown(val, align = PAGE_SIZE)
  val - (val & (align - 1))
end

def alignup(val, align = PAGE_SIZE)
  val.nobits?(align - 1) ? val : (aligndown(val, align) + align)
end

def cstr(str, start)
  pstr = str.slice(start, str.num_bytes)
  stop = pstr.index "\x00"
  pstr[0...stop]
end

def sync_sec_to_seg(shdr, phdr)
  phdr.p_offset = shdr.sh_offset.to_i
  phdr.p_vaddr = phdr.p_paddr = shdr.sh_addr.to_i
  phdr.p_filesz = phdr.p_memsz = shdr.sh_size.to_i
end

# segments
# PT_INTERP
# PT_DYNAMIC
# LOAD RW
phdrs = [
  Phdr.new(
    endian: :little,
    elf_class: 64,
    p_type: PT_INTERP,
    p_flags: PF_R,
    p_align: 1
  ),
  Phdr.new(
    endian: :little,
    elf_class: 64,
    p_type: PT_DYNAMIC,
    p_flags: PF_R,
    p_align: 16 # align by one dyn entry
  ),
  Phdr.new(
    endian: :little,
    elf_class: 64,
    p_type: PT_LOAD,
    p_flags: PF_R | PF_W,
    p_align: PAGE_SIZE
  )
]

def dyn_tag_as_str(d_tag: nil, d_val: nil)
  (dyn = ELFTools::Structs::ELF_Dyn.new(elf_class: 64, endian: :little)).assign(d_tag: d_tag, d_val: d_val)
  dyn.to_binary_s
end

def new_shdr(**vals)
  shdr = Shdr.new(endian: :little, elf_class: 64)
  shdr.assign(vals)
  shdr
end

section_data = [
  ['.shstrtab', "\x00.dynamic\x00.interp\x00.dynstr\x00.shstrtab\x00"],
  ['.dynstr', "\x00/tmp/p1:/tmp/p2:/tmp/p3\x00"],
  ['.interp', "/lib64/ld-2.30.so\x00"],
  [
    '.dynamic',
    # averwrite d_val for DT_STRTAB later, reserving for proper space calculation
    # there is code below which depends on DT_STRTAB being at index 0.
    (dyn_tag_as_str(d_tag: DT_STRTAB, d_val: 0) +
     dyn_tag_as_str(d_tag: DT_RUNPATH, d_val: 1) +
     dyn_tag_as_str(d_tag: DT_NULL, d_val: 0))
  ]
].to_h do |(k, s)|
  aligned_len = alignup(s.size, section_alignment)
  [k, BinData::String.new(s, length: aligned_len)]
end

shstrtab = section_data['.shstrtab']

# sections
#  NULL
#  .dynamic
#  .interp
#  .dynstr
#  .shstrtab
shdrs = [
  new_shdr(
    sh_name: shstrtab.index(".shstrtab\x00"),
    sh_type: SHT_STRTAB,
    sh_addralign: section_alignment
  ),
  new_shdr(
    sh_name: shstrtab.index(".dynstr\x00"),
    sh_type: SHT_STRTAB,
    sh_addralign: section_alignment
  ),
  new_shdr(
    sh_name: shstrtab.index(".interp\x00"),
    sh_type: SHT_PROGBITS,
    sh_addralign: section_alignment
  ),
  new_shdr(
    sh_name: shstrtab.index(".dynamic\x00"),
    sh_type: SHT_DYNAMIC,
    sh_link: 2, # .dynstr
    sh_addralign: section_alignment,
    sh_entsize: 16
  )
]

ehdr = ELF_Ehdr.new(endian: :little, elf_class: 64)
ehdr.assign(
  {
    e_ident: {
      magic: ELFMAG,
      ei_class: 2, # 64
      ei_data: 1, # little
      ei_version: 1,
      # we don't care
      ei_osabi: 0,
      ei_abiversion: 0,
      ei_padding: "\x00" * 7
    },
    e_type: ET_EXEC,
    e_machine: EM_X86_64,
    e_version: 1,
    e_entry: 0x4000,
    e_phoff: 64,
    e_shoff: 0,
    e_flags: 0,
    e_ehsize: 64,
    e_phentsize: phdrs.first.num_bytes,
    e_phnum: phdrs.count,
    e_shentsize: shdrs.first.num_bytes,
    e_shnum: shdrs.count + 1, # NULL section
    e_shstrndx: 0 # will be updated below
  }
)

ehdr.e_shoff = ehdr.num_bytes + (ehdr.e_phnum * ehdr.e_phentsize)
section_data_off = ehdr.num_bytes + (ehdr.e_phnum * ehdr.e_phentsize) + (ehdr.e_shentsize * ehdr.e_shnum)
section_addr_off = START_ADDR + section_data_off

skip = 0
shstrtab = section_data['.shstrtab']

ordered_sec_data = []
shdrs.each_with_index do |shdr, idx|
  sec_name = cstr(shstrtab, shdr.sh_name)
  sec_data = section_data[sec_name]

  # consider null section
  ehdr.e_shstrndx = idx + 1 if sec_name == '.shstrtab'

  matching_phdr_type = {
    '.interp' => PT_INTERP,
    '.dynamic' => PT_DYNAMIC
  }[sec_name]

  shdr.sh_addr = section_addr_off + skip
  shdr.sh_offset = section_data_off + skip
  shdr.sh_size = sec_data.num_bytes

  if matching_phdr_type
    phdrs.find { |phdr| phdr.p_type == matching_phdr_type }&.tap do |phdr|
      sync_sec_to_seg(shdr, phdr)
    end
  end

  skip += shdr.sh_size
  ordered_sec_data << sec_data
end

phdrs.find { |phdr| phdr.p_type == PT_LOAD }.tap do |phdr|
  phdr.p_offset = 0
  phdr.p_vaddr = phdr.p_paddr = START_ADDR
  phdr.p_filesz = phdr.p_memsz = section_data_off + ordered_sec_data.sum(&:length)
end

# NULL section header
shdrs.unshift(BinData::String.new(length: shdrs.first.num_bytes))

File.open(OUT_ELF, 'wb') do |f|
  [ehdr, *phdrs, *shdrs, *ordered_sec_data].each do |p|
    p.write(f)
  end

  shdrs.shift # throw out null

  strtab_addr = shdrs.find { |s| cstr(shstrtab, s.sh_name) == '.dynstr' }.sh_addr
  dyn = dyn_tag_as_str(d_tag: DT_STRTAB, d_val: strtab_addr)
  dynamic = shdrs.find { |s| cstr(shstrtab, s.sh_name) == '.dynamic' }

  # DT_STRTAB is assume to be at index 0
  f.seek(dynamic.sh_offset)
  f.write(dyn)
end
puts "Saved to #{OUT_ELF}"
