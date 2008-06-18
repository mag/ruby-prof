Gem::Specification.new do |spec|
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

  spec.version = "0.6.1"

  spec.authors = ["Shugo Maeda", "Charlie Savage"]
  spec.email = "shugo@ruby-lang.org and cfis@savagexi.com"
  spec.platform = Gem::Platform::RUBY
  spec.require_path = "lib"
  spec.bindir = "bin"
  spec.executables = ["ruby-prof"]
  spec.extensions = ["ext/extconf.rb"]
  spec.files = FileList[
    'Rakefile',
    'README',
    'LICENSE',
    'CHANGES',
    'bin/*',
    'lib/**/*',
    'rails_plugin/**/*',
    'examples/*',
    'ext/*',
    'doc/**/*',
    'test/*'
  ].to_a

  spec.test_files = Dir["test/test_*.rb"]

  spec.required_ruby_version = '>= 1.8.4'
  spec.date = "2008-06-18"
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
