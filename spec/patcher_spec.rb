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

  describe 'interpreter=' do
    def test_interpreter(file, str, filename)
      patcher = get_patcher(file)
      patcher.interpreter = str
      patcher.save(filename)
      expect(described_class.new(filename).get(:interpreter)).to eq str
      File.open(filename) do |f|
        expect(ELFTools::ELFFile.new(f).section_by_name('.interp').data).to eq str + "\x00"
      end
    end

    it 'no interpreter' do
      expect { hook_logger { get_patcher('libtest.so').interpreter = 'a' } }.to output(<<-EOS).to_stdout
[WARN] No interpreter found.
      EOS
    end

    it 'different patched length' do
      with_tempfile do |tmp|
        # Both PIE and no-PIE should be tested
        %w[pie.elf nopie.elf].each do |f|
          test_interpreter(f, '~test~', tmp)
          test_interpreter(f, 'A' * 30, tmp) # slightly larger than the original interp
          # test_interpreter(f, 'A' * 0x1001, tmp) # very large, need extend bin
        end
      end
    end

    it 'still executable after patching' do
      linux_only!

      with_tempfile do |tmp|
        %w[pie.elf nopie.elf].each do |f|
          patcher = get_patcher(f)
          patcher.interpreter = patcher.get(:interpreter) + "\x00" + 'A' * 10
          patcher.save(tmp)
          expect(`#{tmp} < /dev/null`).to eq "It works!\n"
          expect($CHILD_STATUS.exitstatus).to eq 217
        end
      end
    end
  end
end
