#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'timeout'
require 'test_helper'


def simple(n)
  sleep(1)
  n -= 1
  return if n == 0
  simple(n)
end

def factorial(n)
  if n < 2 then
    n
  else 
    n * factorial(n-1)
  end
end


# --  Tests ----
class RecursiveTest < Test::Unit::TestCase
  def test_recursive
    result = RubyProf.profile do
      simple(3)
    end
   
    result.threads.values.each do |methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
  
  def test_factorial
    result = RubyProf.profile do
      # Around 700 on windows causes "stack level too deep" error
      factorial(650)
    end
   
    result.threads.values.each do |methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end   
end
