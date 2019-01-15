require 'elftools/segments/load_segment'
require 'elftools/structs'

require 'patchelf/mm'

describe PatchELF::MM do
  def make_load(off, filesz, vaddr, memsz, perm)
    header = ELFTools::Structs::ELF_Phdr[64].new(endian: :little)
    header.p_offset = off
    header.p_filesz = filesz
    header.p_vaddr = vaddr
    header.p_memsz = memsz
    header.p_flags = perm_to_flag(perm)
    ELFTools::Segments::LoadSegment.new(header, nil)
  end

  def perm_to_flag(perm)
    f = 0
    f |= 1 if perm.include?('x')
    f |= 2 if perm.include?('w')
    f |= 4 if perm.include?('r')
    f
  end

  def test_dispatch(request_size, loads, &block)
    elf = {}
    allow(elf).to receive(:segments_by_type).and_return loads
    obj = allow(elf).to receive(:each_segments)
    loads.each { |seg| obj.and_yield(seg) }
    allow(elf).to receive(:each_sections) {} # do nothing
    ehdr = ELFTools::Structs::ELF_Ehdr.new(endian: :little)
    ehdr.elf_class = 64
    allow(elf).to receive(:header).and_return ehdr

    mm = described_class.new(elf)
    mm.malloc(request_size, &block)
    mm.dispatch!
  end

  # Normal ELF, with R-X and RW- LOADs.
  describe 'normal case' do
    it 'fgap' do
      loads = [make_load(0, 0x666, 0x1000, 0x666, 'rx'), make_load(0x668, 8, 0x2668, 8, 'rw')]
      called = 0
      test_dispatch(2, loads) do |off, vaddr|
        expect(off).to be 0x666
        expect(vaddr).to be 0x2666
        called += 1
      end
      expect(loads[1].file_head).to be 0x666
      expect(called).to be 1
    end

    it 'mgap' do
      loads = [make_load(0, 0x666, 0x1000, 0x666, 'rx'), make_load(0x668, 8, 0x2668, 8, 'rw')]
      called = 0
      test_dispatch(0x100, loads) do |off, vaddr|
        expect(off).to be 0x668
        expect(vaddr).to be 0x1668
        called += 1
      end
      expect(loads[1].file_head).to be 0x668
      expect(called).to be 1
    end
  end

  describe 'extend backwardly' do
    it 'fgap' do
      loads = [make_load(0, 0x666, 0x1000, 0x666, 'rwx'), make_load(0x668, 8, 0x2668, 8, 'rw')]
      called = 0
      test_dispatch(2, loads) do |off, vaddr|
        expect(off).to be 0x666
        expect(vaddr).to be 0x1666
        called += 1
      end
      expect(loads[0].file_tail).to be 0x668
      expect(loads[1].file_head).to be 0x668
      expect(called).to be 1
    end

    it 'mgap' do
      loads = [make_load(0, 0x666, 0x1000, 0x666, 'rw'), make_load(0x668, 8, 0x2668, 8, 'r')]
      called = 0
      test_dispatch(0x200, loads) do |off, vaddr|
        expect(off).to be 0x666
        expect(vaddr).to be 0x1666
        called += 1
      end
      expect(loads[0].file_tail).to be 0x866
      expect(loads[1].file_head).to be 0x1668
      expect(called).to be 1

      # We should be able to extend it again!
      # This time the fgap should be used
      test_dispatch(0x200, loads) {}
      expect(loads[0].file_tail).to be 0xa66
      expect(loads[1].file_head).to be 0x1668
    end
  end

  describe 'abnormal ELF' do
    it 'no LOAD' do
      expect { test_dispatch(1, []) }.to raise_error(ArgumentError)
    end

    it 'out of order' do
      expect { test_dispatch(1, [make_load(1, 1, 1, 1, 'rw'), make_load(0, 0, 0, 0, 'rw')]) }
        .to raise_error(ArgumentError)
    end
  end
end
