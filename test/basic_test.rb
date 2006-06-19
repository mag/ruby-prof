#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

class C1
  def C1.hello
  end
  
  def hello
  end
end

module M1
  def hello
  end
end

class C2
  include M1
  extend M1
end

class C3
  def hello
  end
end


class BasicTest < Test::Unit::TestCase
  def test_double_profile
    RubyProf.start
    assert_raise(RuntimeError) do
    	RubyProf.start
    end
    
    assert_raise(RuntimeError) do
      RubyProf.profile do
        puts 1
      end
    end
    RubyProf.stop
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
    
    # Length should be 5 - one for top level,
    # one for Class.new, 1 for Object.initialize
    # one for Class.hello and one for Class.new.hello
    assert_equal(5, methods.length)
    
    # Check class method
    method1 = methods['<Class:C1>#hello']
    assert_not_nil(method1)
    
    # Check instance method
    method1 = methods['C1#hello']
    assert_not_nil(method1)
  end
  
  def test_module_methods
    result = RubyProf.profile do
	  	C2.hello
	    C2.new.hello
    end
  
    methods = result.threads.values.first
   
    # Length should be 4 - one for top level,
    # one for Class.new, 1 for Object.initialize
    # one for Class.hello  and Class.new.hello
    # (remember, they are the same methdo so are 
		#  combined)
    assert_equal(4, methods.length)
    
    # Check class method
    method1 = methods['M1.hello']
    assert_not_nil(method1)
    assert_equal(2, method1.called)
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
    method1 = methods['<Object:C3>#hello']
    assert_not_nil(method1)
  end
end
