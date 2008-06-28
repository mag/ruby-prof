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
    assert u >= t, [t, u].inspect
  end

  def test_wall_time
    t = RubyProf.measure_wall_time
    assert_kind_of Float, t

    u = RubyProf.measure_wall_time
    assert u >= t, [t, u].inspect
  end

  if RubyProf::CPU_TIME
    def test_cpu_time
      RubyProf.cpu_frequency = 2.33e9

      t = RubyProf.measure_cpu_time
      assert_kind_of Float, t

      u = RubyProf.measure_cpu_time
      assert u >= t, [t, u].inspect
    end
  end

  if RubyProf::ALLOCATIONS
    def test_allocations
      t = RubyProf.measure_allocations
      assert_kind_of Integer, t

      u = RubyProf.measure_allocations
      assert u >= t, [t, u].inspect
    end
  end

  if RubyProf::MEMORY
    def test_memory
      t = RubyProf.measure_memory
      assert_kind_of Integer, t

      u = RubyProf.measure_memory
      assert u >= t, [t, u].inspect
    end
  end
end
