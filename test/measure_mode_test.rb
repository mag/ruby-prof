#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'
require 'prime'


# --  Tests ----
class MeasureModeTest < Test::Unit::TestCase

  def test_process_time
    RubyProf::measure_mode = RubyProf::PROCESS_TIME
    assert_equal(RubyProf::PROCESS_TIME, RubyProf::measure_mode)
    result = RubyProf.profile do
      run_primes
    end
    
    result.threads.each do |thread_id, methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
  
  def test_wall_time
    RubyProf::measure_mode = RubyProf::WALL_TIME
    assert_equal(RubyProf::WALL_TIME, RubyProf::measure_mode)
    result = RubyProf.profile do
      run_primes
    end
    
    result.threads.values.each do |methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
  
  def test_cpu
    return unless RubyProf.constants.include?('CPU_TIME')
    
    RubyProf::measure_mode = RubyProf::CPU_TIME
    assert_equal(RubyProf::CPU_TIME, RubyProf::measure_mode)
    result = RubyProf.profile do
      run_primes
    end
    
    result.threads.values.each do |methods|
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
  
  def test_allocated_objects
    return if RubyProf::ALLOCATIONS.nil?
    
    RubyProf::measure_mode = RubyProf::ALLOCATIONS
    
    assert_equal(RubyProf::ALLOCATIONS, RubyProf::measure_mode)
    
    result = RubyProf.profile do
      Array.new
    end
  end

  def test_memory
    return unless RubyProf::MEMORY

    RubyProf::measure_mode = RubyProf::MEMORY

    assert_equal(RubyProf::MEMORY, RubyProf::measure_mode)

    result = RubyProf.profile do
      Array.new
    end
  end

  def test_invalid
    assert_raise(ArgumentError) do
      RubyProf::measure_mode = 7777
    end
  end
end
