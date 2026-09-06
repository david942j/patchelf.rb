# frozen_string_literal: true

require 'open3'

require 'patchelf/cli'
require 'patchelf/version'

describe PatchELF::CLI do
  it 'invalid input' do
    status = nil
    expect { hook_logger { status = described_class.work(%w[--pi file_not_exists]) } }.to output(<<-EOS).to_stdout
[ERROR] No such file or directory @ rb_sysopen - file_not_exists
    EOS
    expect(status).to eq 1
  end

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
    status = nil
    expect { hook_logger { status = described_class.work(%w[--version]) } }.to output(<<-EOS).to_stdout
PatchELF Version #{PatchELF::VERSION}
    EOS
    expect(status).to eq 0
  end

  it 'help' do
    status = nil
    expect { status = described_class.work(%w[--help]) }.to output(
      /\AUsage: patchelf\.rb \[OPTIONS\] INPUT_FILE \[OUTPUT_FILE\]\n(?=.*-h, --help)(?=.*--version)/m
    ).to_stdout
    expect(status).to eq 0
  end

  it 'accepts an unambiguous long version-option abbreviation' do
    status = nil
    expect { status = described_class.work(%w[--vers]) }.to output(
      "PatchELF Version #{PatchELF::VERSION}\n"
    ).to_stdout
    expect(status).to eq 0
  end

  it 'does not treat a required option argument named --help as a help request' do
    status = nil
    expect { status = described_class.work(%w[--add-needed --help]) }.to output(
      /\AUsage: patchelf\.rb \[OPTIONS\] INPUT_FILE \[OUTPUT_FILE\]/
    ).to_stdout
    expect(status).to eq 1
  end

  it 'treats an option-like path after -- as the input file' do
    patcher = instance_double(PatchELF::Patcher, save: nil)
    expect(PatchELF::Patcher).to receive(:new).with('--version').and_return(patcher)

    expect(described_class.work(%w[-- --version])).to eq 0
  end

  it 'no input file' do
    status = nil
    expect { hook_logger { status = described_class.work(%w[--pi]) } }.to output(
      /\AUsage: patchelf\.rb \[OPTIONS\] INPUT_FILE \[OUTPUT_FILE\]/
    ).to_stdout
    expect(status).to eq 1
  end

  it 'returns a clean error when patching fails' do
    patcher = instance_double(PatchELF::Patcher)
    allow(PatchELF::Patcher).to receive(:new).and_return(patcher)
    allow(patcher).to receive(:save).and_raise(PatchELF::PatchError, 'cannot rewrite ELF')

    status = nil
    expect { hook_logger { status = described_class.work(['input.elf']) } }
      .to output("[ERROR] cannot rewrite ELF\n").to_stdout
    expect(status).to eq 1
  end

  it 'returns a clean error for an unsupported patch operation' do
    patcher = instance_double(PatchELF::Patcher)
    allow(PatchELF::Patcher).to receive(:new).and_return(patcher)
    allow(patcher).to receive(:save).and_raise(NotImplementedError, 'operation not implemented')

    status = nil
    expect { hook_logger { status = described_class.work(['input.elf']) } }
      .to output("[ERROR] operation not implemented\n").to_stdout
    expect(status).to eq 1
  end

  it 'set interpreter' do
    with_tempfile do |tmp|
      described_class.work(['--interp', 'AAAAA', bin_path('pie.elf'), tmp])
      expect { hook_logger { described_class.work(['--pi', tmp]) } }.to output(<<-EOS).to_stdout
interpreter: AAAAA
      EOS
    end
  end

  it 'set needed' do
    with_tempfile do |tmp|
      described_class.work(['--needed', 'libc1,libc2,libc3',
                            '--add-needed', 'add',
                            '--remove-needed', 'libc1',
                            '--replace-needed', 'libc2,replace',
                            bin_path('pie.elf'), tmp])
      expect { hook_logger { described_class.work(['--pn', tmp]) } }.to output(<<-EOS).to_stdout
needed: replace libc3 add
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

  describe 'executable' do
    def run_executable(*args)
      root = File.expand_path('..', __dir__)
      Open3.capture3(Gem.ruby, "-I#{File.join(root, 'lib')}", File.join(root, 'bin/patchelf.rb'), *args)
    end

    it 'returns a non-zero status without a Ruby backtrace for an invalid option' do
      stdout, stderr, status = run_executable('--not-an-option')

      expect(stdout).to be_empty
      expect(stderr).to include('[ERROR] invalid option: --not-an-option')
      expect(stderr).not_to include('lib/patchelf/cli.rb')
      expect(status.exitstatus).to eq 1
    end

    it 'returns a non-zero status for too many positional arguments' do
      stdout, stderr, status = run_executable(bin_path('pie.elf'), 'output.elf', 'extra')

      expect(stdout).to be_empty
      expect(stderr).to include('[ERROR] invalid argument: too many positional arguments')
      expect(status.exitstatus).to eq 1
    end

    it 'returns a non-zero status when the input does not exist' do
      stdout, stderr, status = run_executable('--pi', 'file_not_exists')

      expect(stdout).to be_empty
      expect(stderr).to include('[ERROR]', 'file_not_exists')
      expect(status.exitstatus).to eq 1
    end

    it 'returns a non-zero status without a Ruby backtrace for a directory input' do
      stdout, stderr, status = run_executable('--pi', File.join(__dir__, 'files'))

      expect(stdout).to be_empty
      expect(stderr).to include('[ERROR]', 'Is a directory')
      expect(stderr).not_to include('lib/patchelf/cli.rb')
      expect(status.exitstatus).to eq 1
    end
  end
end
