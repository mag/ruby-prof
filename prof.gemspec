Gem::Specification.new do |spec|
  spec.name = "prof"
  spec.version = "0.4"
  spec.summary = "Fast profiler for Ruby"
  spec.author = "Shugo Maeda"
  spec.email = "shugo@ruby-lang.org"
  spec.autorequire = "prof"
  spec.files = ["prof.c", "extconf.rb", "lib/unprof.rb", "README"]
  spec.extensions << "extconf.rb"
  spec.test_files = []
  spec.has_rdoc = false
end
