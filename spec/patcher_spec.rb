# encoding: ascii-8bit

require 'elftools'

require 'patchelf/patcher'

describe PatchELF::Patcher do
  def get_patcher(filename)
    described_class.new(File.join(__dir__, 'files', filename))
  end

  it 'get' do
    patcher = get_patcher('libtest.so')
    expect(patcher.get(:soname)).to eq 'libtest.so.217'
    expect(patcher.get(:needed)).to eq %w[libstdc++.so.6 libc.so.6]
    expect { hook_logger { patcher.get(:interpreter) } }.to output("[WARN] No interpreter found.\n").to_stdout

    expect(get_patcher('pie.elf').get(:interpreter)).to eq '/lib64/ld-linux-x86-64.so.2'
  end

  def test_interpreter(patcher, str, filename)
    patcher.interpreter = str
    patcher.save(filename)
    expect(described_class.new(filename).get(:interpreter)).to eq str
    File.open(filename) do |f|
      expect(ELFTools::ELFFile.new(f).section_by_name('.interp').data).to eq str + "\x00"
    end
  end

  describe 'interpreter=' do
    it 'no interpreter' do
      expect { hook_logger { get_patcher('libtest.so').interpreter = 'a' } }.to output(<<-EOS).to_stdout
[WARN] No interpreter found.
      EOS
    end

    it 'short' do
      patcher = get_patcher('pie.elf')
      with_tempfile do |tmp|
        test_interpreter(patcher, '~test~', tmp)
      end
    end
  end
end
