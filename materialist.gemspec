# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'materialist'

Gem::Specification.new do |spec|
  spec.name          = 'materialist'
  spec.version       = Materialist::VERSION
  spec.authors       = ['Mo Valipour']
  spec.email         = ['valipour@gmail.com']
  spec.summary       = %q{Utilities to materialize routemaster topics}
  spec.homepage      = 'http://github.com/deliveroo/materialist'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.test_files    = spec.files.grep(%r{^spec/})
  spec.require_paths = %w(lib)

  spec.add_runtime_dependency 'sidekiq'
  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'routemaster-drain', '>= 3.0'

  spec.add_development_dependency 'dotenv'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'webmock'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'appraisal'
end
