# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'patchelf/version'

Gem::Specification.new do |s|
  s.name          = 'patchelf'
  s.version       = PatchELF::VERSION
  s.summary       = 'patchelf'
  s.description   = <<-EOS
  A simple utility for modifying existing ELF executables and
libraries.
  EOS
  s.license       = 'MIT'
  s.authors       = ['david942j']
  s.email         = ['david942j@gmail.com']
  s.files         = Dir['lib/**/*.rb'] + Dir['bin/*'] + %w[README.md]
  s.homepage      = 'https://github.com/david942j/patchelf.rb'
  s.executables   = ['patchelf.rb']

  s.required_ruby_version = '>= 3.1'

  s.add_runtime_dependency 'elftools', '>= 1.3'

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rspec', '~> 3'
  s.add_development_dependency 'rubocop', '~> 1'
  # https://github.com/codeclimate/test-reporter/issues/413
  s.add_development_dependency 'simplecov', '~> 0.17', '< 0.23'
  s.add_development_dependency 'tty-platform', '~> 0.1'
  s.add_development_dependency 'yard', '~> 0.9'
  s.metadata['rubygems_mfa_required'] = 'true'
end
