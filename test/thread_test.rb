#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'timeout'
require 'test_helper'

# --  Tests ----
class ThreadTest < Test::Unit::TestCase
  def test_thread_timings
    RubyProf.start
    
    sleep(2)    

    thread = Thread.new do
      sleep(2)
    end
    
    thread.join
    
    result = RubyProf.stop
  end

  def test_thread
    RubyProf.start
    
    begin
      status = Timeout::timeout(2) do
        while true
          next
        end
      end
    rescue Timeout::Error
    end
   
    result = RubyProf.stop
    
    result.threads.values.each do |methods|
      methods.values.each do |method|
        check_parent_times(method)
        check_parent_calls(method)
        check_child_times(method)   
      end
    end
  end
end
