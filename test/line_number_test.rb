#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'prime'
require 'test_helper'

class Foo
  def method1
    a = 3
  end
  
  def method2
    method1
  end
  
  def method3
    sleep(1)
  end
end

# --  Tests ----
class LineNumbers < Test::Unit::TestCase
  def test_function_line_no
    foo = Foo.new
    
    result = RubyProf.profile do
      foo.method2
    end

    methods = result.threads.values.first.sort.reverse
    assert_equal(3, methods.length)
    
    method = methods[0]
    assert_equal('LineNumbers#test_function_line_no', method.full_name)
    assert_equal(28, method.line)
    
    method = methods[2]
    assert_equal('Foo#method2', method.full_name)
    assert_equal(13, method.line)
    
    method = methods[1]
    assert_equal('Foo#method1', method.full_name)
    assert_equal(9, method.line)
  end
  
  def test_c_function
    foo = Foo.new
    
    result = RubyProf.profile do
      foo.method3
    end

    methods = result.threads.values.first.sort.reverse
    assert_equal(3, methods.length)
    
    method = methods[0]
    assert_equal('LineNumbers#test_c_function', method.full_name)
    assert_equal(51, method.line)
    
    method = methods[1]
    assert_equal('Foo#method3', method.full_name)
    assert_equal(17, method.line)
    
    method = methods[2]
    assert_equal('Kernel#sleep', method.full_name)
    assert_equal(0, method.line)
  end
end