#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'prime'
require 'test_helper'


# --  Tests ----
class PrimeTest < Test::Unit::TestCase
  def test_consistency
    length = 500
    maxnum = 10000
    result = RubyProf.profile do
		  random_array = make_random_array(length, maxnum)
		  primes = find_primes(random_array)
	  	largest = find_largest(primes)
    end
    
    result.threads.values.each do |methods|
			methods.values.each do |method|
    		check_parent_times(method)
    		check_parent_calls(method)
    		check_child_times(method)		
			end
  	end
  end
end