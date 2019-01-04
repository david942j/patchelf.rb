require 'patchelf/helper'

describe PatchELF::Helper do
  it 'colorize' do
    expect(described_class.color_enabled?).to eq $stderr.tty?
    allow(described_class).to receive(:color_enabled?) { true }
    expect(described_class.colorize('msg', :warn)).to eq "\e[38;5;230mmsg\e[0m"
  end
end
