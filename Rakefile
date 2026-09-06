# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubygems/package'
require 'rubygems/spec_fetcher'
require 'rubocop/rake_task'
require 'tmpdir'
require 'yard'

require_relative 'lib/patchelf/version'

task default: :check
task check: %i[rubocop spec doc package_smoke]

desc 'Verify that RELEASE_TAG matches the gem version'
task :verify_release_tag do
  release_tag = ENV.fetch('RELEASE_TAG')
  expected_tag = "v#{PatchELF::VERSION}"
  abort "release tag #{release_tag} does not match #{expected_tag}" unless release_tag == expected_tag
end

desc 'Verify that the gem version has not already been published'
task :verify_unpublished_version do
  dependency = Gem::Dependency.new('patchelf', "= #{PatchELF::VERSION}")
  matching_specs, errors = Gem::SpecFetcher.fetcher.spec_for_dependency(dependency)
  abort "could not verify published patchelf versions: #{errors.map(&:message).join('; ')}" unless errors.empty?
  abort "patchelf #{PatchELF::VERSION} is already published" unless matching_specs.empty?
end

desc 'Build and smoke-test the packaged gem'
task package_smoke: :build do
  gem_path = File.expand_path("pkg/patchelf-#{PatchELF::VERSION}.gem", __dir__)
  source_paths = [File.expand_path(__dir__), File.expand_path('lib', __dir__)]
  dependency_paths = $LOAD_PATH.reject { |path| source_paths.include?(File.expand_path(path)) }

  Dir.mktmpdir('patchelf-package') do |package_dir|
    Gem::Package.new(gem_path).extract_files(package_dir)
    executable = File.join(package_dir, 'bin/patchelf.rb')
    package_lib = File.join(package_dir, 'lib')
    ruby_lib = [package_lib, *dependency_paths].join(File::PATH_SEPARATOR)
    env = { 'BUNDLE_GEMFILE' => nil, 'PACKAGE_LIB' => package_lib, 'RUBYLIB' => ruby_lib, 'RUBYOPT' => nil }
    load_check = <<~'RUBY'
      require 'patchelf'
      require 'patchelf/cli'
      package_prefix = "#{File.realpath(ENV.fetch('PACKAGE_LIB'))}#{File::SEPARATOR}"
      %w[patchelf.rb patchelf/cli.rb].each do |feature|
        loaded_path = $LOADED_FEATURES.find { |path| path.end_with?("/#{feature}") }
        abort "#{feature} was not loaded" if loaded_path.nil?
        unless File.realpath(loaded_path).start_with?(package_prefix)
          abort "#{feature} loaded from #{loaded_path}, not the packaged gem"
        end
      end
    RUBY

    commands = [
      [Gem.ruby, '--disable-gems', '-e', load_check],
      [Gem.ruby, '--disable-gems', executable, '--version'],
      [Gem.ruby, '--disable-gems', executable, '--print-interpreter', File.expand_path('spec/files/pie.elf', __dir__)]
    ]
    commands.each do |command|
      abort "packaged executable failed: #{command.join(' ')}" unless system(env, *command)
    end
  end
end

RuboCop::RakeTask.new(:rubocop)

RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = './spec/**/*_spec.rb'
end

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = Dir['lib/**/*.rb']
  t.options = ['--fail-on-warning']
  t.stats_options = ['--list-undoc']
end
