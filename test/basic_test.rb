#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

# Need to use wall time for this test due to the sleep calls
RubyProf::measure_mode = RubyProf::WALL_TIME

class C1
  def C1.hello
    sleep(0.1)
  end
  
  def hello
    sleep(0.2)
  end
end

module M1
  def hello
    sleep(0.3)
  end
end

class C2
  include M1
  extend M1
end

class C3
  def hello
    sleep(0.4)
  end
end

module M4
  def hello
    sleep(0.5)
  end
end

module M5
  include M4
  def goodbye
    hello
  end
end

class C6
  include M5
  def test
    goodbye
  end
end

class BasicTest < Test::Unit::TestCase
  def test_running
    assert(!RubyProf.running?)
    RubyProf.start
    assert(RubyProf.running?)
    RubyProf.stop
    assert(!RubyProf.running?)
  end
  
  def test_double_profile
    RubyProf.start
    assert_nothing_raised do
      RubyProf.start
    end

    assert_nothing_raised do
      RubyProf.profile do
        puts 1
      end
    end

    assert_raise(RuntimeError) do
      RubyProf.stop
    end
  end
  
  def test_no_block
    assert_raise(ArgumentError) do
      RubyProf.profile
    end
  end
  
  def test_class_and_instance_methods
    result = RubyProf.profile do
      C1.hello
      C1.new.hello
    end
    
    methods = result.threads.values.first
    
    # Length should be 7:
    #   1 test_class_and_instance_methods (this method)
    #   1 Class.new
    #   1 Class:Object allocate
    #   1 for Object.initialize
    #   1 for Class hello
    #   1 for Object hello
    #   1 sleep
    assert_equal(7, methods.length)
    
    # Check the names
    methods = methods.sort.reverse
    
    assert_equal('BasicTest#test_class_and_instance_methods', methods[0].full_name)
    assert_equal('Kernel#sleep', methods[1].full_name)
    assert_equal('C1#hello', methods[2].full_name)
    assert_equal('<Class::C1>#hello', methods[3].full_name)
    
    # The last three methods have total times of zero
    assert_equal(0, methods[4].total_time)
    assert_equal(0, methods[5].total_time)
    assert_equal(0, methods[6].total_time)
    
    #assert_equal('Class#new', methods[4].full_name)
    #assert_equal('<Class::Object>#allocate', methods[5].full_name)
    #assert_equal('Object#initialize', methods[6].full_name)
  end
  
  def test_module_methods
    result = RubyProf.profile do
      C2.hello
      C2.new.hello
    end
  
    methods = result.threads.values.first
   
    # Length should be 6:
    #   1 BasicTest#test_module_methods (this method)
    #   1 Class#new
    #   1 <Class::Object>#allocate
    #   1 Object#initialize
    #   1 M1#hello
    #   1 Kernel#sleep

    assert_equal(6, methods.length)

    # Check the names
    methods = methods.sort.reverse
    
    assert_equal('BasicTest#test_module_methods', methods[0].full_name)
    assert_equal('Kernel#sleep', methods[1].full_name)
    assert_equal('M1#hello', methods[2].full_name)
    
    # The last three methods have times of zero
    assert_equal(0, methods[3].total_time)
    assert_equal(0, methods[4].total_time)
    assert_equal(0, methods[5].total_time)
    
    #assert_equal('<Class::Object>#allocate', methods[3].full_name)
    #assert_equal('Class#new', methods[4].full_name)
    #assert_equal('Object#initialize', methods[5].full_name)
  end
  
  def test_singleton
    c3 = C3.new
    
    class << c3
      def hello
      end
    end
  
    result = RubyProf.profile do
      c3.hello
    end
  
    methods = result.threads.values.first
    
    # Length should be 2 - one for top level
    # and one for the singleton method.
    assert_equal(2, methods.length)
    
    # Check singleton method
    methods = methods.sort.reverse
    
    assert_equal('BasicTest#test_singleton', methods[0].full_name)
    assert_equal('<Object::C3>#hello', methods[1].full_name)
  end
  
  def test_traceback
    RubyProf.start
    assert_raise(NoMethodError) do
      RubyProf.xxx
    end
    
    RubyProf.stop
  end   
end
