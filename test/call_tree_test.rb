require 'ruby-prof'
require 'prime1'

def runtest
  result = RubyProf.profile do
    run_primes
  end

  printer = RubyProf::CallTreePrinter.new(result)
  f = open('run1.calltree','w')
  #printer.print(f)
  f.close
end

def multiple_runs
  (1..10).each { |i| runtest }
end

runtest


