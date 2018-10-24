Gem::Specification.new do |spec|
  spec.name          = 'lazy_mapper'
  spec.version       = '0.3.1'
  spec.summary       = 'A lazy object mapper'
  spec.description   = 'Wraps primitive data in a semantically rich model'
  spec.authors       = ['Adam Lett']
  spec.email         = 'adam@bruun-rasmussen.dk'
  spec.homepage      = 'https://github.com/bruun-rasmussen/lazy_mapper'
  spec.license       = 'MIT'
  spec.files         = `git ls-files -z`.split("\x0") - ['bin/console']
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rspec'
end
