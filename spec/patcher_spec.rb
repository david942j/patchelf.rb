# encoding: ascii-8bit
# frozen_string_literal: true

require 'digest'
require 'elftools'

require 'patchelf/patcher'

describe PatchELF::Patcher do
  def get_patcher(filename, logging: true)
    described_class.new(bin_path(filename), logging: logging)
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
  end

  describe 'interpreter=' do
    it 'no interpreter' do
      expect { hook_logger { get_patcher('libtest.so').interpreter = 'a' } }.to output(<<-EOS).to_stdout
[WARN] No interpreter found.
      EOS

      patcher = get_patcher('libtest.so', logging: false)
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
      expect { get_patcher('libtest.so', logging: false).interpreter }.to raise_error(PatchELF::MissingSegmentError)
      expect { get_patcher('static.elf', logging: false).needed }.to raise_error(PatchELF::MissingSegmentError)
    end

    it 'raises missing segment when queried for DT_tag' do
      patcher = get_patcher('static.elf', logging: false)
      expect { patcher.runpath }.to raise_error(PatchELF::MissingSegmentError)
      expect { patcher.soname }.to raise_error(PatchELF::MissingSegmentError)
    end

    it 'missing dynamic tag' do
      expect { get_patcher('rpath.elf', logging: false).runpath }.to raise_error(PatchELF::MissingTagError)
      expect { get_patcher('rpath.elf', logging: false).soname }.to raise_error(PatchELF::MissingTagError)
    end
  end
end
