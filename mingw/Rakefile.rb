# We can't use Ruby's standard build procedures
# on Windows because the Ruby executable is
# built with VC++ while here we want to build
# with MingW.  So just roll our own...

require 'rake/clean'
require 'rbconfig'

RUBY_INCLUDE_DIR = Config::CONFIG["archdir"]
RUBY_BIN_DIR = Config::CONFIG["bindir"]
RUBY_LIB_DIR = Config::CONFIG["libdir"]
RUBY_SHARED_LIB = Config::CONFIG["LIBRUBY"]
RUBY_SHARED_DLL = RUBY_SHARED_LIB.gsub(/lib$/, 'dll')
    
CLEAN.include('*.o')
CLOBBER.include('ruby_prof.so')

task :default => "ruby_prof"

SRC = FileList['../ext/*.c']
OBJ = SRC.collect do |file_name|
  File.basename(file_name).ext('o')
end

SRC.each do |srcfile|
  objfile = File.basename(srcfile).ext('o')
  file objfile => srcfile do
    command = "gcc -c -fPIC -O2 -Wall -o #{objfile} #{srcfile} -I#{RUBY_INCLUDE_DIR}"
    sh "sh -c '#{command}'" 
  end
end

file "ruby_prof" => OBJ do
  command = "gcc -shared -o ruby_prof.so #{OBJ} #{RUBY_BIN_DIR}/#{RUBY_SHARED_DLL}" 
  sh "sh -c '#{command}'" 
end
