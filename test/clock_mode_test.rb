#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'
require 'prime'


# --  Tests ----
class ClockModeTest < Test::Unit::TestCase
  def test_clock
    return
    RubyProf::clock_mode = RubyProf::CLOCK
    assert_equal(RubyProf::CLOCK, RubyProf::clock_mode)
    result = RubyProf.profile do
			run_primes
		end
		
		print_results(result)
    
    result.threads.values.each do |methods|
			methods.values.each do |method|
    		check_parent_times(method)
    		check_parent_calls(method)
    		check_child_times(method)		
			end
  	end
  end
  
  def test_gettimeofday
    return
    RubyProf::clock_mode = RubyProf::GETTIMEOFDAY
    assert_equal(RubyProf::GETTIMEOFDAY, RubyProf::clock_mode)
    result = RubyProf.profile do
			run_primes
		end
    
		print_results(result)
		
    result.threads.values.each do |methods|
			methods.values.each do |method|
    		check_parent_times(method)
    		check_parent_calls(method)
    		check_child_times(method)		
			end
  	end
  end
  
  def test_cpu
    #return
    RubyProf::clock_mode = RubyProf::CPU
    assert_equal(RubyProf::CPU, RubyProf::clock_mode)
    result = RubyProf.profile do
			run_primes
		end
    
		print_results(result)
		
    result.threads.values.each do |methods|
			methods.values.each do |method|
    		check_parent_times(method)
    		check_parent_calls(method)
    		check_child_times(method)		
			end
  	end
  end
  
  def test_invalid
    assert_raise(ArgumentError) do
    	RubyProf::clock_mode = 7777
    end
  end
end