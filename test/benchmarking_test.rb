#!/usr/bin/env ruby
require 'test/unit'
require 'ruby-prof'
require 'test_helper'
require 'prime'

class BenchmarkingTest < Test::Unit::TestCase
  def setup
    raise 'RubyProf should not be running' if RubyProf.running?
    RubyProf.benchmarking = true
  end

  def teardown
    RubyProf.stop if RubyProf.running?
    RubyProf.benchmarking = false
  end

  def test_boolean_benchmarking_flag
    assert RubyProf.benchmarking?
    RubyProf.benchmarking = false
    assert !RubyProf.benchmarking?
  end

  def test_cant_set_benchmarking_flag_during_run
    RubyProf.start
    assert_raise(RuntimeError) do
      RubyProf.benchmarking = false
    end
  end

  def test_stop_returns_total_time
    result = RubyProf.profile { 'abc' * 5 }
    assert_kind_of Float, result
    assert_equal RubyProf.total_time, result
  end

  def test_accumulates_until_next_start
    assert_equal 0, RubyProf.total_time

    first = RubyProf.resume { 'abc' * 5 }
    assert_kind_of Float, first
    assert_equal RubyProf.total_time, first
    assert first > 0

    second = RubyProf.profile { 'def' * 10 }
    assert second > first
    assert_equal RubyProf.total_time, second
  end
end
