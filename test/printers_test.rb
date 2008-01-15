#!/usr/bin/env ruby
require 'test/unit'
require 'ruby-prof'
require 'prime'
require 'test_helper'


# --  Tests ----
class PrintersTest < Test::Unit::TestCase
  
  def setup
    @result = RubyProf.profile do
      run_primes
    end
  end
    
  def test_printers
    printer = RubyProf::FlatPrinter.new(@result)
    printer.print(STDOUT)
    
    printer = RubyProf::GraphHtmlPrinter.new(@result)
    printer.print
    
    printer = RubyProf::GraphPrinter.new(@result)
    printer.print
    
    printer = RubyProf::CallTreePrinter.new(@result)
    printer.print(STDOUT)

    # we should get here
    assert(true)
  end

  def test_flatprinter_duckfriendliness
    output = ''
    
    printer = RubyProf::FlatPrinter.new(@result)
    assert_nothing_raised { printer.print( output ) }
    
    assert_match( /Thread ID: \d+/i, output )
    assert_match( /Total: \d+\.\d+/i, output )
    assert_match( /Object#run_primes/i, output )
  end
    
  def test_graphhtmlprinter_duckfriendliness
    output = ''
    printer = RubyProf::GraphHtmlPrinter.new(@result)
    assert_nothing_raised { printer.print(output) }

    assert_match( /DTD HTML 4\.01/i, output )
    assert_match( %r{<th>Total Time</th>}i, output )
    assert_match( /Object#run_primes/i, output )
  end
    
  def test_graphprinter_duckfriendliness
    output = ''
    printer = RubyProf::GraphPrinter.new(@result)
    assert_nothing_raised { printer.print(output) }

    assert_match( /Thread ID: \d+/i, output )
    assert_match( /Total Time: \d+\.\d+/i, output )
    assert_match( /Object#run_primes/i, output )
  end
    
  def test_calltreeprinter_duckfriendliness
    output = ''
    printer = RubyProf::CallTreePrinter.new(@result)
    assert_nothing_raised { printer.print(output) }

    assert_match( /fn=Object::find_primes/i, output )
    assert_match( /events: process_time/i, output )
  end

end
