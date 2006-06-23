#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

class DuplicateNames < Test::Unit::TestCase
  def test_names
    result = RubyProf::profile do
     	str = %{module Foo; class Bar; def foo; end end end}

     	eval str
			Foo::Bar.new.foo
			DuplicateNames.class_eval {remove_const :Foo}

			eval str
			Foo::Bar.new.foo
			DuplicateNames.class_eval {remove_const :Foo}

			eval str
			Foo::Bar.new.foo
		end
		print_results(result)
		
		# There should be 3 foo methods
		methods = result.threads.values.first
		
		method_info = methods['DuplicateNames::Foo::Bar#foo']
		assert_not_nil(method_info)
		
		method_info = methods['DuplicateNames::Foo::Bar#foo-1']
		assert_not_nil(method_info)
		
		method_info = methods['DuplicateNames::Foo::Bar#foo-2']
		assert_not_nil(method_info)
	end
end
