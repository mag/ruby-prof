#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'


# --  Tests ----
class ClockModeTest < Test::Unit::TestCase
  def test_clock
    #RubyProf::clock_mode = RubyProf::CLOCK
    #assert_equal(RubyProf::CLOCK, RubyProf::clock_mode)
    result = RubyProf.profile do
			run_primes
		end
    
    result.threads.values.each do |methods|
			methods.values.each do |method|
    		check_parent_times(method)
    		check_parent_calls(method)
    		check_child_times(method)		
			end
  	end
  end
  
  def test_gettimeofday
    RubyProf::clock_mode = RubyProf::GETTIMEOFDAY
    assert_equal(RubyProf::GETTIMEOFDAY, RubyProf::clock_mode)
#    result = RubyProf.profile do
	#		run_primes
		#end
    
    #result.threads.values.each do |methods|
			#methods.values.each do |method|
    		#check_parent_times(method)
    		#check_parent_calls(method)
    		#check_child_times(method)		
			#end
  	#end
  end
  
  def test_cpu
    RubyProf::clock_mode = RubyProf::CPU
    assert_equal(RubyProf::CPU, RubyProf::clock_mode)
#    result = RubyProf.profile do
	#		run_primes
		#end
    
    #result.threads.values.each do |methods|
			#methods.values.each do |method|
    		#check_parent_times(method)
    		#check_parent_calls(method)
    		#check_child_times(method)		
			#end
  	#end
  end
  
  def test_invalid
    assert_raise(ArgumentError) do
    	RubyProf::clock_mode = 7777
    end
  end
end