#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

# Need to use wall time for this test due to the sleep calls
RubyProf::measure_mode = RubyProf::WALL_TIME

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


class TimingTest < Test::Unit::TestCase

  def test_basic
    result = RubyProf.profile do
      method1
    end
    print_results(result)

    assert_equal(1, result.threads.length)

    methods = result.threads.values.first
    assert_equal(3, methods.length)

    
    methods = methods.sort.reverse
    
    method = methods[0]
    assert_equal('TimingTest#test_basic', method.full_name)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(1, method.children_time, 0.02)
    assert_equal(0, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)
    
    method = methods[1]
    assert_equal('Object#method1', method.full_name)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(1, method.children.length)
    
    method = methods[2]
    assert_equal('Kernel#sleep', method.full_name)
    assert_in_delta(1, method.total_time, 0.02)
    assert_in_delta(1, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(0, method.children.length)
  end
  
  def test_timings
    result = RubyProf.profile do
      method3
    end

    assert_equal(1, result.threads.length)
    methods = result.threads.values.first
    assert_equal(5, methods.length)
    
    methods = methods.sort.reverse

    method = methods[0]
    assert_equal('TimingTest#test_timings', method.full_name)
    assert_in_delta(7, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(7, method.children_time, 0.02)
    assert_equal(0, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)
    
    method = methods[1]
    assert_equal('Kernel#sleep', method.full_name)
    assert_in_delta(7, method.total_time, 0.02)
    assert_in_delta(7, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(4, method.called)
    assert_equal(3, method.parents.length)
    assert_equal(0, method.children.length)
    
    method = methods[2]
    assert_equal('Object#method3', method.full_name)
    assert_in_delta(7, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(7, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(3, method.children.length)
    
    method = methods[3]
    assert_equal('Object#method2', method.full_name)
    assert_in_delta(3, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(3, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(2, method.children.length)
    
    method = methods[4]
    assert_equal('Object#method1', method.full_name)
    assert_in_delta(2, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(2, method.children_time, 0.02)
    assert_equal(2, method.called)
    assert_equal(2, method.parents.length)
    assert_equal(1, method.children.length)
  end
end
