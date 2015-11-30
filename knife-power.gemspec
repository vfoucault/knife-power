# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'knife-power/version'

Gem::Specification.new do |spec|
  spec.name          = "knife-power"
  spec.version       = Knife::Power::VERSION
  spec.authors       = ["Vianney Foucault"]
  spec.email         = ["vianney.foucault@gmail.com"]
  spec.homepage      = "https://github.com/vfoucault/knife-power"
  spec.summary       = %q{PowerVM Management}
  spec.description   = "knife plugin to automate lpar setup & creation"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "chef", "~> 12.0"
  spec.add_dependency "net-ssh", "~> 2.6"
  spec.add_dependency "json-schema", "~> 2.5"
  spec.add_dependency "ruby-ip", '~> 0.9', ">= 0.9.3"
  spec.add_dependency "ruby-progressbar", '~> 1.7', ">= 1.7.5"

  spec.add_development_dependency 'rspec-core', '~> 0'
  spec.add_development_dependency 'rspec-expectations', '~> 0'
  spec.add_development_dependency 'rspec-mocks', '~> 0'
  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake', '~>0'
  spec.add_development_dependency 'pry', '~>0'
end
