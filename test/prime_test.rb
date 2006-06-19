#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'prime'
require 'test_helper'


# --  Tests ----
class PrimeTest < Test::Unit::TestCase
  def test_consistency
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
end