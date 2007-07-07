#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'


def simple(n)
  sleep(1)
  n -= 1
  return if n == 0
  simple(n)
end

def cycle(n)
  sub_cycle(n)
end

def sub_cycle(n)
  sleep(1)
  n -= 1
  return if n == 0
  cycle(n)
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
      simple(2)
    end
    
    result.threads.values.each do |methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
    
    methods = result.threads.values.first.sort.reverse
    assert_equal(6, methods.length)   

    method = methods[0]
    assert_equal('RecursiveTest#test_recursive', method.full_name)
    assert_in_delta(2, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(2, method.children_time, 0.02)
    assert_equal(0, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)

    method = methods[1]
    assert_equal('Object#simple', method.full_name)
    assert_in_delta(2, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(2, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(4, method.children.length)
    
    method = methods[2]
    assert_equal('Kernel#sleep', method.full_name)
    assert_in_delta(2, method.total_time, 0.02)
    assert_in_delta(2, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(2, method.called)
    assert_equal(2, method.parents.length)
    assert_equal(0, method.children.length)
    
    method = methods[3]
    assert_equal('Object#simple-1', method.full_name)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(1, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(3, method.children.length)
    
    method = methods[4]
    assert_equal('Fixnum#==', method.full_name)
    assert_in_delta(0, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(2, method.called)
    assert_equal(2, method.parents.length)
    assert_equal(0, method.children.length)
    
    method = methods[5]
    assert_equal('Fixnum#-', method.full_name)
    assert_in_delta(0, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(2, method.called)
    assert_equal(2, method.parents.length)
    assert_equal(0, method.children.length)
  end
  
  def test_cycle
    result = RubyProf.profile do
      cycle(2)
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
