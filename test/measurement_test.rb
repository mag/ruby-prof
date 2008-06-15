#!/usr/bin/env ruby
require 'test/unit'
require 'ruby-prof'
require 'test_helper'

class MeasurementTest < Test::Unit::TestCase
  def setup
    GC.enable_stats if GC.respond_to?(:enable_stats)
  end

  def teardown
    GC.disable_stats if GC.respond_to?(:disable_stats)
  end

  def test_process_time
    t = RubyProf.measure_process_time
    assert_kind_of Float, t

    u = RubyProf.measure_process_time
    assert u > t, [t, u].inspect
  end

  def test_process_time
    t = RubyProf.measure_wall_time
    assert_kind_of Float, t

    u = RubyProf.measure_wall_time
    assert u > t, [t, u].inspect
  end

  def test_cpu_time
    return unless RubyProf::CPU_TIME
    RubyProf.cpu_frequency = 2.33e9

    t = RubyProf.measure_cpu_time
    assert_kind_of Float, t

    u = RubyProf.measure_cpu_time
    assert u > t, [t, u].inspect
  end

  def test_allocations
    return unless RubyProf::ALLOCATIONS

    t = RubyProf.measure_allocations
    assert_kind_of Integer, t

    u = RubyProf.measure_allocations
    assert u > t, [t, u].inspect
  end

  def test_memory
    return unless RubyProf::MEMORY

    t = RubyProf.measure_memory
    assert_kind_of Integer, t

    u = RubyProf.measure_memory
    assert u > t, [t, u].inspect
  end
end
