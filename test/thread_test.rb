#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'timeout'
require 'test_helper'

# Need to use wall time for this test due to the sleep calls
RubyProf::measure_mode = RubyProf::WALL_TIME

# --  Tests ----
class ThreadTest < Test::Unit::TestCase
  def test_thread_timings
    RubyProf.start
    
    sleep(2)    

    thread = Thread.new do
      sleep(0.5)
      sleep(2)
    end
    
    thread.join
    
    result = RubyProf.stop

    values = result.threads.values.sort do |value1, value2|
      value1.length <=> value2.length
    end
    
    # Check background thread
    methods = values.first.sort.reverse
    assert_equal(2, methods.length)
    
    method = methods[0]
    assert_equal('ThreadTest#test_thread_timings', method.full_name)
    assert_in_delta(2.5, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0.5, method.wait_time, 0.02)
    assert_in_delta(2.0, method.children_time, 0.02)
    assert_equal(0, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(1, method.children.length)

    method = methods[1]
    assert_equal('Kernel#sleep', method.full_name)
    assert_in_delta(2.5, method.total_time, 0.02)
    assert_in_delta(2.0, method.self_time, 0.02)
    assert_in_delta(0.5, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(2, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(0, method.children.length)
    
    # Check foreground thread
    methods = values.last.sort.reverse
    assert_equal(5, methods.length)
    methods = methods.sort.reverse
    
    method = methods[0]
    assert_equal('ThreadTest#test_thread_timings', method.full_name)
    assert_in_delta(4.5, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(2.0, method.wait_time, 0.02)
    assert_in_delta(2.5, method.children_time, 0.02)
    assert_equal(0, method.called)
    assert_equal(0, method.parents.length)
    assert_equal(3, method.children.length)

    method = methods[1]
    assert_equal('Thread#join', method.full_name)
    assert_in_delta(2.5, method.total_time, 0.02)
    assert_in_delta(0.5, method.self_time, 0.02)
    assert_in_delta(2.0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(0, method.children.length)
    
    method = methods[2]
    assert_equal('Kernel#sleep', method.full_name)
    assert_in_delta(2, method.total_time, 0.02)
    assert_in_delta(2.0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(0, method.children.length)
    
    
    method = methods[3]
    assert_equal('Thread#initialize', method.full_name)
    assert_in_delta(0, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(0, method.children.length)
    
    method = methods[4]
    assert_equal('<Class::Thread>#new', method.full_name)
    assert_in_delta(0, method.total_time, 0.02)
    assert_in_delta(0, method.self_time, 0.02)
    assert_in_delta(0, method.wait_time, 0.02)
    assert_in_delta(0, method.children_time, 0.02)
    assert_equal(1, method.called)
    assert_equal(1, method.parents.length)
    assert_equal(1, method.children.length)
  end

  def test_thread
    result = RubyProf.profile do 
      begin
        status = Timeout::timeout(2) do
          while true
            next
          end
        end
      rescue Timeout::Error
      end
    end
    
    printer = RubyProf::GraphHtmlPrinter.new(result)
    File.open('c:/temp/test.html', 'w') do |file|
      printer.print(file)
    end
    
    result.threads.each do |thread_id, methods|
      STDOUT << "thread: " << thread_id << "\n"
      methods.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
end
