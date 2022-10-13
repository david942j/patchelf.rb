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
          expect(Digest::MD5.digest(File.binread(f1))).to eq Digest::MD5.digest(File.binread(f2))
        end
      end
    end

    it 'patchelf_compatible: true ' do
      patcher = get_patcher('pef-compat.elf')
      patcher.interpreter = '/hippy/lib64/ld-2.30.sour'
      with_tempfile do |f1|
        # TODO: exception is thrown by new_load_method, update after new_load_method implementation
        expect { patcher.save(f1) }.to raise_error NotImplementedError
        patcher.save(f1, patchelf_compatible: true)
        expect(described_class.new(f1).interpreter).to eq patcher.interpreter

        new_runpath = "#{patcher.runpath}:no:no:no"
        patcher.runpath = new_runpath
        # TODO: exception is thrown by new_load_method, update after new_load_method implementation
        expect { patcher.save(f1) }.to raise_error NotImplementedError
        patcher.save(f1, patchelf_compatible: true)
        expect(described_class.new(f1).runpath).to eq new_runpath
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

    shared_examples 'still executable after patching' do |saver_args = {}|
      it 'still executable after patching' do
        linux_only!

        %w[pie.elf nopie.elf].each do |f|
          [0x100, 0xfff].each do |pad_len|
            patcher = get_patcher(f)
            patcher.interpreter = "#{patcher.interpreter}\x00".ljust(pad_len, 'A')
            with_tempfile do |tmp|
              patcher.save(tmp, **saver_args)
              expect(`#{tmp} < /dev/null`).to eq "It works!\n"
              expect($CHILD_STATUS.exitstatus).to eq 217
            end
          end
        end
      end
    end

    context('patchelf_compatible: false') do
      it_behaves_like 'still executable after patching'

      it 'patches fine but segfaults on execution' do
        linux_only!

        patcher = get_patcher('syncthing')
        # TODO: don't run this test on other arch.
        patcher.interpreter = "/lib64/ld-linux-x86-64.so.2\x00"
        patcher.rpath = patcher.rpath.gsub('@@HOMEBREW_PREFIX@@', '')
        with_tempfile do |tmp|
          patcher.save(tmp)
          expect(`#{tmp} --version`).to eq ''
          expect($CHILD_STATUS.termsig).to eq Signal.list['SEGV']
        end
      end
    end

    context 'patchelf_compatible: true' do
      it_behaves_like 'still executable after patching', { patchelf_compatible: true }

      it 'patches and runs fine' do
        linux_only!

        patcher = get_patcher('syncthing')
        # TODO: don't run this test on other arch.
        patcher.interpreter = "/lib64/ld-linux-x86-64.so.2\x00"
        patcher.rpath = patcher.rpath.gsub('@@HOMEBREW_PREFIX@@', '')
        with_tempfile do |tmp|
          patcher.save(tmp, patchelf_compatible: true)
          expect(`#{tmp} --version`).to include('syncthing v1.4.0 "Fermium Flea"')
          expect($CHILD_STATUS.exitstatus).to eq 0
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

    context 'patchelf_compatible: true' do
      it 'normal' do
        name = 'lwo'
        with_tempfile do |tmp|
          patcher = get_patcher('libtest.so')
          patcher.soname = name
          # TODO: update after implementing modify_soname in AltSaver
          expect { patcher.save(tmp, patchelf_compatible: true) }.to raise_error NotImplementedError
        end
      end
    end
  end

  describe 'runpath=' do
    shared_examples 'runpath=' do |saver_args = {}|
      it 'runpath exist' do
        patcher = get_patcher('runpath.elf')
        patcher.runpath = 'XD'
        with_tempfile do |tmp|
          patcher.save(tmp, **saver_args)
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
          patcher.save(tmp, **saver_args)
          expect(described_class.new(tmp).runpath).to eq 'XD'
        end
      end

      it 'runpath and rpath both not exist' do
        patcher = get_patcher('nopie.elf', on_error: :silent)
        expect(patcher.rpath).to be_nil
        expect(patcher.runpath).to be_nil
        patcher.runpath = 'XD'
        with_tempfile do |tmp|
          patcher.save(tmp, **saver_args)
          expect(described_class.new(tmp).runpath).to eq 'XD'
        end
      end

      it 'with use_rpath' do
        patcher = get_patcher('rpath.elf').use_rpath!
        expect(patcher.runpath).to eq '/not_exists:/lib:/pusheen/is/fat'
        patcher.runpath = 'XD'
        with_tempfile do |tmp|
          patcher.save(tmp, **saver_args)
          expect(described_class.new(tmp).use_rpath!.runpath).to eq 'XD'
        end
      end
    end

    context 'patchelf_compatible: false' do
      it_behaves_like 'runpath='
    end

    context 'patchelf_compatible: true' do
      it_behaves_like 'runpath=', { patchelf_compatible: true }

      it 'force converts DT_RPATH to DT_RUNPATH when DT_RUNPATH is missing' do
        patcher = get_patcher('rpath.elf', on_error: :silent)
        expect(patcher.runpath).to be_nil
        patcher.runpath = 'XD'

        with_tempfile do |tmp|
          patcher.save(tmp, patchelf_compatible: true)
          saved_patcher = described_class.new(tmp, on_error: :silent)
          expect(saved_patcher.rpath).to be_nil
          expect(saved_patcher.runpath).to eq 'XD'
        end
      end

      it 'force converts DT_RPATH to DT_RUNPATH, even when old_rpath = new_rpath' do
        patcher = get_patcher('rpath.elf', on_error: :silent)
        expect(patcher.runpath).to be_nil
        patcher.runpath = patcher.rpath

        with_tempfile do |tmp|
          patcher.save(tmp, patchelf_compatible: true)
          saved_patcher = described_class.new(tmp, on_error: :silent)
          expect(saved_patcher.rpath).to be_nil
          expect(saved_patcher.runpath).to eq patcher.rpath
        end
      end
    end
  end

  describe 'rpath=' do
    shared_examples 'rpath=' do |saver_args = {}|
      it 'overwrites rpath' do
        patcher = get_patcher('rpath.elf')
        patcher.rpath = 'o O' # picking different sym to avoid confusion
        with_tempfile do |tmp|
          patcher.save tmp, **saver_args
          expect(described_class.new(tmp).rpath).to eq 'o O'
        end
      end

      it 'runpath and rpath both not exist' do
        patcher = get_patcher('nopie.elf', on_error: :silent)
        expect(patcher.rpath).to be_nil
        expect(patcher.runpath).to be_nil
        patcher.rpath = 'o O'
        with_tempfile do |tmp|
          patcher.save(tmp, **saver_args)
          expect(described_class.new(tmp).rpath).to eq 'o O'
        end
      end
    end

    context 'patchelf_compatible: false' do
      it_behaves_like 'rpath='

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

    context 'patchelf_compatible: true' do
      it_behaves_like 'rpath=', { patchelf_compatible: true }

      it 'writing to rpath force deletes runpath' do
        patcher = get_patcher('runpath.elf', on_error: :silent)
        patcher.rpath = 'o O'
        with_tempfile do |tmp|
          patcher.save tmp, patchelf_compatible: true

          saved_patcher = described_class.new(tmp, on_error: :silent)
          expect(saved_patcher.runpath).to be_nil
          expect(saved_patcher.rpath).to eq 'o O'
        end
      end
    end
  end

  describe 'nosection' do
    shared_examples 'patching with no section' do |saver_args = {}|
      it 'set interp' do
        patcher = get_patcher('nosection.elf')
        patcher.interpreter = 'ppp'
        with_tempfile do |tmp|
          patcher.save(tmp, **saver_args)
          expect(described_class.new(tmp).interpreter).to eq 'ppp'
        end
      end
    end

    context 'patchelf_compatible: false' do
      it_behaves_like 'patching with no section'
    end

    context 'patchelf_compatible: true' do
      it_behaves_like 'patching with no section', { patchelf_compatible: true }
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

    it 'patchelf_compatible: true' do
      with_tempfile do |tmp|
        patcher = get_patcher('pie.elf')
        patcher.add_needed('juice')
        # TODO: update after implementing modify_needed in AltSaver
        expect { patcher.save(tmp, patchelf_compatible: true) }.to raise_error NotImplementedError
      end
    end
  end

  describe 'raises exception' do
    it 'missing segment' do
      error = PatchELF::MissingSegmentError
      expect { get_patcher('libtest.so', on_error: :exception).interpreter }.to raise_error(error)
      expect { get_patcher('static.elf', on_error: :exception).needed }.to raise_error(error)
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
