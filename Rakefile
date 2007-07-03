require 'rubygems'
require 'rake/gempackagetask'
require 'rake/rdoctask'

SO_NAME = "ruby_prof.so"

# ------- Default Package ----------
RUBY_PROF_VERSION = "0.5.0"

FILES = FileList[
  'Rakefile',
  'README',
  'LICENSE',
  'CHANGES',
  'bin/*',
  'lib/**/*',
  'examples/*',
  'ext/*',
  'doc/**/*',
  'test/*'
]

# Default GEM Specification
default_spec = Gem::Specification.new do |spec|
  spec.name = "ruby-prof"
  
  spec.homepage = "http://rubyforge.org/projects/ruby-prof/"
  spec.summary = "Fast Ruby profiler"
  spec.description = <<-EOF
ruby-prof is a fast code profiler for Ruby. It is a C extension and
therefore is many times faster than the standard Ruby profiler. It
supports both flat and graph profiles.  For each method, graph profiles
show how long the method ran, which methods called it and which 
methods it called. RubyProf generate both text and html and can output
it to standard out or to a file.
EOF

  spec.version = RUBY_PROF_VERSION

  spec.author = "Shugo Maeda and Charlie Savage"
  spec.email = "shugo@ruby-lang.org and cfis@savagexi.com"
  spec.platform = Gem::Platform::RUBY
  spec.require_path = "lib" 
  spec.bindir = "bin"
  spec.executables = ["ruby-prof"]
  spec.extensions = ["ext/extconf.rb"]
  spec.autorequire = "ruby-prof"
  spec.files = FILES.to_a
  spec.test_files = Dir["test/test_*.rb"]
  

  spec.required_ruby_version = '>= 1.8.4'
  spec.date = DateTime.now
  spec.rubyforge_project = 'ruby-prof'
  
  # rdoc
  spec.has_rdoc = true
  spec.rdoc_options << "--title" << "ruby-prof"
  # Show source inline with line numbers
  spec.rdoc_options << "--inline-source" << "--line-numbers"
  # Make the readme file the start page for the generated html
  spec.rdoc_options << '--main' << 'README'
  spec.extra_rdoc_files = ['bin/ruby-prof',
                           'ext/ruby_prof.c',
                           'examples/flat.txt',
                           'examples/graph.txt',
                           'examples/graph.html',
                           'README',
                           'LICENSE']

end


# Rake task to build the default package
Rake::GemPackageTask.new(default_spec) do |pkg|
  pkg.need_tar = true
  pkg.need_zip = true
end


# ------- Windows Package ----------

# Windows specification
win_spec = default_spec.clone
win_spec.extensions = []
win_spec.platform = Gem::Platform::WIN32
win_spec.files += ["lib/#{SO_NAME}"]


desc "Create Windows Gem"
task :create_win32_gem do
  # Copy the win32 extension built by MingW - easier to install
  # since there are no dependencies of msvcr80.dll
  current_dir = File.expand_path(File.dirname(__FILE__))
  source = File.join(current_dir, "mingw", SO_NAME)
  target = File.join(current_dir, "lib", SO_NAME)
  cp(source, target)

  # Create the gem, then move it to pkg
  Gem::Builder.new(win_spec).build
  gem_file = "#{win_spec.name}-#{win_spec.version}-#{win_spec.platform}.gem"
  mv(gem_file, "pkg/#{gem_file}")

  # Remove win extension from top level directory  
  rm(target)
end


task :package => :create_win32_gem

# ---------  RDoc Documentation ------
desc "Generate rdoc documentation"
Rake::RDocTask.new("rdoc") do |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.title    = "ruby-prof"
  # Show source inline with line numbers
  rdoc.options << "--inline-source" << "--line-numbers"
  # Make the readme file the start page for the generated html
  rdoc.options << '--main' << 'README'
  rdoc.rdoc_files.include('bin/**/*',
                          'doc/*.rdoc',
                          'examples/flat.txt',
                          'examples/graph.txt',
                          'examples/graph.html',
                          'lib/**/*.rb',
                          'ext/**/ruby_prof.c',
                          'README',
                          'LICENSE')
end


# ---------  Publish to RubyForge  ----------------
desc "Publish ruby-prof to RubyForge."
task :publish do 
  require 'rake/contrib/sshpublisher'
  
  # Get ruby-prof path
  ruby_prof_path = File.expand_path(File.dirname(__FILE__))

  publisher = Rake::SshDirPublisher.new("cfis@rubyforge.org",
        "/var/www/gforge-projects/ruby-prof", ruby_prof_path)
end
