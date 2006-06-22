#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

def method1
	sleep(1)
end

def method2
	sleep(2)
	method1
end
  
def method3
	sleep(3)
	method2
	method1
end

# Need to use wall time for this test due to the sleep calls
RubyProf::clock_mode = RubyProf::WALL_TIME

class TimingTest < Test::Unit::TestCase

  def test_basic
    result = RubyProf.profile do
      method1
    end
    
    assert_equal(1, result.threads.length)

    methods = result.threads.values.first
    assert_equal(3, methods.length)
    
    method = methods['#toplevel']
    assert_not_nil(method)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(1, method.called, 0.02)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)

    method = methods['Object#method1']
    assert_not_nil(method)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(1, method.children.length)
    
    sleep = methods['Kernel#sleep']
    assert_not_nil(sleep)
    assert_in_delta(1, sleep.total_time, 0.02)
    assert_in_delta(1, sleep.self_time, 0.02)
    assert_in_delta(0, sleep.children_time, 0.02)
    assert_equal(1, sleep.called)
    assert_equal(1, sleep.parents.length)
    assert_equal(0, sleep.children.length)
  end
  
  def test_timings
    result = RubyProf.profile do
      method3
    end
    
    assert_equal(1, result.threads.length)
    methods = result.threads.values.first
    assert_equal(5, methods.length)

    method = methods['#toplevel']
    assert_not_nil(method)
    assert_in_delta(7, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(7, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)
    
    method = methods['Object#method3']
    assert_not_nil(method)
    assert_in_delta(7, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(7, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(3, method.children.length)
  end
end
