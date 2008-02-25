#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'

class ExceptionsTest < Test::Unit::TestCase
  def test_profile
    puts "test_profile"
    result = begin
      RubyProf.profile do 
        raise(RuntimeError, 'Test error')
      end
    rescue => e
    end    
    assert_not_nil(result)
    puts result
  end
end
