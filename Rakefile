require "rake"
require "rake/clean"
require "rubygems/package_task"
require "rdoc/task"
require "rspec/core/rake_task"
require "fileutils"
include FileUtils

##############################################################################
# Configuration
##############################################################################
NAME = "arpie"
VERS = "0.0.6"
CLEAN.include ["**/.*.sw?", "pkg", ".config", "rdoc", "coverage"]
RDOC_OPTS = ["--quiet", "--line-numbers", "--inline-source", '--title', \
  "#{NAME}: A high-performing layered networking protocol framework. Simple to use, simple to extend.", \
  '--main', 'README.rdoc']

DOCS = ["README.rdoc", "COPYING", "BINARY.rdoc"]

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += RDOC_OPTS
  rdoc.rdoc_files.add DOCS + ["doc/*.rdoc", "lib/**/*.rb"]
end

desc "Packages up #{NAME}"
task :package => [:clean]

spec = Gem::Specification.new do |s|
  s.name = NAME
  s.rubyforge_project = "#{NAME}"
  s.version = VERS
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = DOCS + Dir["doc/*.rdoc"]
  s.rdoc_options += RDOC_OPTS + ["--exclude", "^(examples|extras)\/"]
  s.summary = "A high-performing layered networking protocol framework. Simple to use, simple to extend."
  s.description = s.summary
  s.author = "Bernhard Stoeckner"
  s.email = "elven@swordcoast.net"
  s.homepage = "http://#{NAME}.elv.es"
  s.executables = []
  s.required_ruby_version = ">= 1.8.4"
  s.files = Dir.glob("{bin,doc,spec,lib,tools,scripts,data}/**/*")
  s.require_path = "lib"
  s.bindir = "bin"
  s.add_dependency('uuidtools', '>= 1.0.7')
end

Gem::PackageTask.new(spec) do |p|
  p.need_tar = true
  p.gem_spec = spec
end

desc "Run specs with coverage"
RSpec::Core::RakeTask.new("spec") do |t|
  t.pattern = "spec/*_spec.rb"
  t.rspec_opts  = File.read("spec/spec.opts").split("\n")
  t.rcov_opts  = File.read("spec/rcov.opts").split("\n")
  t.rcov = true
end

desc "Run specs without coverage"
task :default => [:spec_no_cov]
RSpec::Core::RakeTask.new("spec_no_cov") do |t|
  t.pattern = "spec/*_spec.rb"
  t.rspec_opts  = File.read("spec/spec.opts").split("\n")
end

desc "Run rcov only"
RSpec::Core::RakeTask.new("rcov") do |t|
  t.pattern = "spec/*_spec.rb"
  t.rcov_opts  = File.read("spec/rcov.opts").split("\n")
  t.rspec_opts  = File.read("spec/spec.opts").split("\n")
  t.rcov = true
end

desc "check documentation coverage"
task :dcov do
  sh "find lib -name '*.rb' | xargs dcov"
end
