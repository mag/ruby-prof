#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'


module Foo
  def Foo::hello
  end
end

module Bar
  def Bar::hello
    Foo::hello
  end
  
  def hello
    Bar::hello
  end
end

include Bar

class ModuleTest < Test::Unit::TestCase
  def test_nested_modules
    result = RubyProf.profile do
      hello
    end

    methods = result.threads.values.first
    methods = methods.sort.reverse
      
    # Length should be 4
    assert_equal(4, methods.length)
    
    method = methods[0]
    assert_equal('#toplevel', method.name)
    
    method = methods[1]
    assert_equal('Bar#hello', method.name)
    
    method = methods[2]
    assert_equal('<Module::Bar>#hello', method.name)
    
    method = methods[3]
    assert_equal('<Module::Foo>#hello', method.name)
  end 
end
