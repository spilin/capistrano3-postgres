# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capistrano3/postgres/version'

Gem::Specification.new do |spec|
  spec.name          = "capistrano3-postgres"
  spec.version       = Capistrano3::Postgres::VERSION
  spec.authors       = ["Alex Krasynskyi"]
  spec.email         = ["lyoshakr@gmail.com"]
  spec.summary       = %q{Create, download and restore postgres database. }
  spec.description   = %q{Create postgres dumps, download and replicate locally.}
  spec.homepage      = "https://github.com/spilin/capistrano3-postgres"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "capistrano", "~> 3.0"
end
