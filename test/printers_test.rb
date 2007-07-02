#!/usr/bin/env ruby
require 'test/unit'
#require 'ruby-prof'
require 'C:/Development/msys/src/ruby-prof/vc/Debug/ruby_prof.so'
require 'C:/Development/msys/src/ruby-prof/lib/ruby-prof/graph_printer.rb'
require 'C:/Development/msys/src/ruby-prof/lib/ruby-prof/graph_html_printer.rb'
require 'C:/Development/msys/src/ruby-prof/lib/ruby-prof/flat_printer.rb'
require 'C:/Development/msys/src/ruby-prof/lib/ruby-prof/call_tree_printer.rb'
require 'prime'
require 'test_helper'


# --  Tests ----
class PrintersTest < Test::Unit::TestCase
  def test_printer
    result = RubyProf.profile do
      run_primes
    end
    
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
    
    printer = RubyProf::GraphHtmlPrinter.new(result)
    File.open('c:/temp/test.html', 'w') do |file|
      printer.print(file)
    end
    
    printer = RubyProf::GraphPrinter.new(result)
    File.open('c:/temp/test.txt', 'w') do |file|
      printer.print(file)
    end
    
    printer = RubyProf::CallTreePrinter.new(result)
    printer.print(STDOUT)

    # we should get here
    assert(true)
  end
end
