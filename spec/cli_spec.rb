# frozen_string_literal: true

require 'patchelf/cli'
require 'patchelf/version'

describe PatchELF::CLI do
  it 'print' do
    expect do
      hook_logger do
        described_class.work(%w[--pi --print-needed --print-soname] << bin_path('pie.elf'))
      end
    end.to output(<<-EOS).to_stdout
interpreter: /lib64/ld-linux-x86-64.so.2
needed: libstdc++.so.6 libc.so.6
[WARN] Entry DT_SONAME not found, not a shared library?
    EOS
  end

  it 'force rpath' do
    expect do
      hook_logger do
        described_class.work(%w[--pr --force-rpath] << bin_path('rpath.elf'))
      end
    end.to output(<<-EOS).to_stdout
rpath: /not_exists:/lib:/pusheen/is/fat
    EOS
  end

  it 'version' do
    expect { hook_logger { described_class.work(%w[--version]) } }.to output(<<-EOS).to_stdout
PatchELF Version #{PatchELF::VERSION}
    EOS
  end

  it 'no input file' do
    expect { hook_logger { described_class.work(%w[--pi]) } }.to output(
      described_class.__send__(:option_parser).help
    ).to_stdout
  end

  it 'set interpreter' do
    with_tempfile do |tmp|
      described_class.work(['--interp', 'AAAAA', bin_path('pie.elf'), tmp])
      expect { hook_logger { described_class.work(['--pi', tmp]) } }.to output(<<-EOS).to_stdout
interpreter: AAAAA
      EOS
    end
  end

  it 'set soname' do
    with_tempfile do |tmp|
      expect { hook_logger { described_class.work(['--so', 'A', bin_path('pie.elf'), tmp]) } }
        .to output(<<-EOS).to_stdout
[WARN] Entry DT_SONAME not found, not a shared library?
      EOS

      described_class.work(['--so', 'XDD', bin_path('libtest.so'), tmp])
      expect { hook_logger { described_class.work(['--ps', tmp]) } }.to output(<<-EOS).to_stdout
soname: XDD
      EOS
    end
  end

  it 'set runpath' do
    with_tempfile do |tmp|
      described_class.work(['--runpath', '/xdd', bin_path('runpath.elf'), tmp])
      expect { hook_logger { described_class.work(['--pr', tmp]) } }.to output(<<-EOS).to_stdout
runpath: /xdd
      EOS
    end
  end
end
