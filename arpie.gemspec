# -*- encoding: utf-8 -*-
require File.expand_path('../lib/arpie/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Bernhard Stoeckner"]
  gem.email         = ["le@e-ix.net"]
  gem.description   = %q{Toolkit for handling binary data, network protocols, file formats, and similar}
  gem.summary       = gem.description
  gem.homepage      = "https://github.com/elven/arpie"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "arpie"
  gem.require_paths = ["lib"]
  gem.version       = Arpie::VERSION

  gem.post_install_message = "
    You have installed arpie 0.1.0 or greater. This breaks
    compatibility with previous versions (0.0.x).

    Specifically, it removes all client/server code, and
    XMLRPC integration, since EventMachine and similar does
    all that in a much cleaner and more efficient way.
  "
end
