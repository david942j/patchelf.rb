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
end
