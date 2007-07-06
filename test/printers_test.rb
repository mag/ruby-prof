#!/usr/bin/env ruby
require 'test/unit'
require 'ruby-prof'
require 'prime'
require 'test_helper'


# --  Tests ----
class PrintersTest < Test::Unit::TestCase
  def test_printers
    result = RubyProf.profile do
      run_primes
    end
    
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
    
    printer = RubyProf::GraphHtmlPrinter.new(result)
    printer.print
    
    printer = RubyProf::GraphPrinter.new(result)
    printer.print
    
    printer = RubyProf::CallTreePrinter.new(result)
    printer.print(STDOUT)

    # we should get here
    assert(true)
  end
end
