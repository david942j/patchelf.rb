# frozen_string_literal: true

require 'patchelf/helper'

describe PatchELF::Helper do
  it 'colorize' do
    expect(described_class.color_enabled?).to eq $stderr.tty?
    allow(described_class).to receive(:color_enabled?) { true }
    expect(described_class.colorize('msg', :warn)).to eq "\e[38;5;230mmsg\e[0m"
  end

  it 'aligndown' do
    expect(described_class.aligndown(0x1234)).to be 0x1000
    expect(described_class.aligndown(0x33, 0x20)).to be 0x20
    expect(described_class.aligndown(0x10, 0x8)).to be 0x10
  end

  it 'alignup' do
    expect(described_class.alignup(0x1234)).to be 0x2000
    expect(described_class.alignup(0x33, 0x20)).to be 0x40
    expect(described_class.alignup(0x10, 0x8)).to be 0x10
  end

  it 'returns the target architecture page size' do
    {
      ELFTools::Constants::EM_ALPHA => 0x10000,
      ELFTools::Constants::EM_IA_64 => 0x10000,
      ELFTools::Constants::EM_MIPS => 0x10000,
      ELFTools::Constants::EM_PPC => 0x10000,
      ELFTools::Constants::EM_PPC64 => 0x10000,
      ELFTools::Constants::EM_AARCH64 => 0x10000,
      ELFTools::Constants::EM_TILEGX => 0x10000,
      ELFTools::Constants::EM_LOONGARCH => 0x10000,
      ELFTools::Constants::EM_SPARC => 0x2000,
      ELFTools::Constants::EM_SPARCV9 => 0x2000
    }.each do |e_machine, page_size|
      expect(described_class.page_size(e_machine)).to eq page_size
    end
  end
end
