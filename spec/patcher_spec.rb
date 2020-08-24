# encoding: ascii-8bit
# frozen_string_literal: true

require 'digest'
require 'elftools'

require 'patchelf/patcher'

describe PatchELF::Patcher do
  def get_patcher(filename, on_error: :log)
    described_class.new(bin_path(filename), on_error: on_error)
  end

  it 'get' do
    patcher = get_patcher('libtest.so')
    expect(patcher.soname).to eq 'libtest.so.217'
    expect(patcher.needed).to eq %w[libstdc++.so.6 libc.so.6]
    expect { hook_logger { patcher.interpreter } }.to output("[WARN] No interpreter found.\n").to_stdout

    expect { hook_logger { get_patcher('rpath.elf').runpath } }.to output(<<-EOS).to_stdout
[WARN] Entry DT_RUNPATH not found.
    EOS
    expect(get_patcher('rpath.elf').use_rpath!.runpath).to eq '/not_exists:/lib:/pusheen/is/fat'
    expect(get_patcher('runpath.elf').runpath).to eq '/not_exists:/lib:/pusheen/is/fat'

    expect(get_patcher('pie.elf').interpreter).to eq '/lib64/ld-linux-x86-64.so.2'
  end

  describe 'initializer arguments' do
    it 'accepts one of [:log :silent :exception] as on_error value' do
      accepted_syms = %i[log exception silent]
      accepted_syms.each do |on_error|
        expect { get_patcher('rpath.elf', on_error: on_error) }.not_to raise_error
      end
      expect { get_patcher('rpath.elf', on_error: :nyan) }.to raise_error(ArgumentError)
    end

    it 'returns nil on_error :silent' do
      expect(get_patcher('libtest.so', on_error: :silent).interpreter).to be_nil
      expect(get_patcher('rpath.elf', on_error: :silent).runpath).to be_nil
      expect(get_patcher('runpath.elf', on_error: :silent).rpath).to be_nil
      expect(get_patcher('static.elf', on_error: :silent).soname).to be_nil
    end
  end

  describe 'save' do
    it 'twice' do
      patcher = get_patcher('libtest.so')
      patcher.soname = '.so'.rjust(0x1000, 'long')
      with_tempfile do |f1|
        with_tempfile do |f2|
          patcher.save(f1)
          patcher.save(f2)
          expect(Digest::MD5.digest(IO.binread(f1))).to eq Digest::MD5.digest(IO.binread(f2))
        end
      end
    end

    it 'patchelf_compatible: true ' do
      patcher = get_patcher('pef-compat.elf')
      patcher.interpreter = '/hippy/lib64/ld-2.30.sour'
      with_tempfile do |f1|
        expect { patcher.save(f1) }.to raise_error NotImplementedError
        patcher.save(f1, patchelf_compatible: true)
        expect(described_class.new(f1).interpreter).to eq patcher.interpreter
      end
    end
  end

  describe 'interpreter=' do
    it 'no interpreter' do
      expect { hook_logger { get_patcher('libtest.so').interpreter = 'a' } }.to output(<<-EOS).to_stdout
[WARN] No interpreter found.
      EOS

      patcher = get_patcher('libtest.so', on_error: :exception)
      expect { patcher.interpreter = 'a' }.to raise_error PatchELF::MissingSegmentError
    end

    it 'still executable after patching' do
      linux_only!

      %w[pie.elf nopie.elf].each do |f|
        [0x100, 0xfff].each do |pad_len|
          patcher = get_patcher(f)
          patcher.interpreter = (patcher.interpreter + "\x00").ljust(pad_len, 'A')
          with_tempfile do |tmp|
            patcher.save(tmp)
            expect(`#{tmp} < /dev/null`).to eq "It works!\n"
            expect($CHILD_STATUS.exitstatus).to eq 217
          end
        end
      end
    end
  end

  describe 'soname=' do
    it 'normal' do
      name = 'longlong.so.31337'
      with_tempfile do |tmp|
        patcher = get_patcher('libtest.so')
        patcher.soname = name
        patcher.save(tmp)
        expect(described_class.new(tmp).soname).to eq name
      end
    end
  end

  describe 'runpath=' do
    it 'runpath exist' do
      patcher = get_patcher('runpath.elf')
      patcher.runpath = 'XD'
      with_tempfile do |tmp|
        patcher.save(tmp)
        expect(described_class.new(tmp).runpath).to eq 'XD'
      end
    end

    it 'runpath not exist' do
      patcher = get_patcher('rpath.elf')
      expect { hook_logger { patcher.runpath } }.to output(<<-EOS).to_stdout
[WARN] Entry DT_RUNPATH not found.
      EOS
      patcher.runpath = 'XD'
      with_tempfile do |tmp|
        patcher.save(tmp)
        expect(described_class.new(tmp).runpath).to eq 'XD'
      end
    end

    it 'with use_rpath' do
      patcher = get_patcher('rpath.elf').use_rpath!
      expect(patcher.runpath).to eq '/not_exists:/lib:/pusheen/is/fat'
      patcher.runpath = 'XD'
      with_tempfile do |tmp|
        patcher.save(tmp)
        expect(described_class.new(tmp).use_rpath!.runpath).to eq 'XD'
      end
    end
  end

  describe 'rpath=' do
    it 'overwrites rpath' do
      patcher = get_patcher('rpath.elf')
      patcher.rpath = 'o O' # picking different sym to avoid confusion
      with_tempfile do |tmp|
        patcher.save tmp
        expect(described_class.new(tmp).rpath).to eq 'o O'
      end
    end

    it 'writing to rpath leaves runpath untouched' do
      patcher = get_patcher('runpath.elf')
      patcher.rpath = 'o O'
      with_tempfile do |tmp|
        patcher.save tmp

        saved_patcher = described_class.new(tmp)
        expect(saved_patcher.runpath).to eq patcher.runpath
        expect(saved_patcher.rpath).to eq 'o O'
      end
    end
  end

  describe 'needed' do
    it 'combo' do
      patcher = get_patcher('pie.elf')
      expect(patcher.needed).to eq %w[libstdc++.so.6 libc.so.6]
      patcher.add_needed('added1')
      patcher.add_needed('added2')
      patcher.remove_needed('libc.so.6')
      patcher.replace_needed('libstdc++.so.6', 'replaced')
      patcher.remove_needed('added1')
      expect(patcher.needed).to eq %w[replaced added2]
    end
  end

  describe 'raises exception' do
    it 'missing segment' do
      MissingSegmentError = PatchELF::MissingSegmentError
      expect { get_patcher('libtest.so', on_error: :exception).interpreter }.to raise_error(MissingSegmentError)
      expect { get_patcher('static.elf', on_error: :exception).needed }.to raise_error(MissingSegmentError)
    end

    it 'raises missing segment when queried for DT_tag' do
      patcher = get_patcher('static.elf', on_error: :exception)
      expect { patcher.runpath }.to raise_error(PatchELF::MissingSegmentError)
      expect { patcher.soname }.to raise_error(PatchELF::MissingSegmentError)
    end

    it 'missing dynamic tag' do
      expect { get_patcher('rpath.elf', on_error: :exception).runpath }.to raise_error(PatchELF::MissingTagError)
      expect { get_patcher('rpath.elf', on_error: :exception).soname }.to raise_error(PatchELF::MissingTagError)
    end
  end
end
