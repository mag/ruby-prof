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

class BasicTest < Test::Unit::TestCase
  def test_nested_modules
		result = RubyProf.profile do
			hello
		end

		methods = result.threads.values.first
	    
  	# Length should be 4s
  	assert_equal(4, methods.length)
    
  	method1 = methods['Bar#hello']
  	assert_not_nil(method1)
  	
  	method1 = methods['<Module::Bar>#hello']
  	assert_not_nil(method1)
  	
  	method1 = methods['<Module::Foo>#hello']
  	assert_not_nil(method1)
	end	
end
