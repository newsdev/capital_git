# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capital_git/version'

Gem::Specification.new do |spec|
  spec.name          = "capital_git"
  spec.version       = CapitalGit::VERSION
  spec.authors       = ["Albert Sun"]
  spec.email         = ["Albert.Sun@nytimes.com"]
  spec.license       = "MIT"

  spec.summary       = %q{Talk to git like a database.}
  # spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "https://github.com/newsdev/capital_git"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  # spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.executables   = ["capital_git"]
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "sinatra"
  spec.add_runtime_dependency "json"
  spec.add_runtime_dependency "rugged"
  # spec.add_runtime_dependency "rainbows"
  # gem 'rugged', git: 'git://github.com/libgit2/rugged.git', branch: 'master', submodules: true

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "shotgun"
end
