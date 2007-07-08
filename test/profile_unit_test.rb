#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'
require 'test_helper'
require 'ruby-prof/profile_test_case'

# Need to use wall time for this test due to the sleep calls
RubyProf::measure_mode = RubyProf::WALL_TIME

# --  Tests ----
class ProfileTest < Test::Unit::TestCase
  def test_profile
    sleep(2)    
  end

  def teardown
    profile_dir = output_directory
    assert(File.exists?(profile_dir))
    
    file_path = File.join(profile_dir, 'test_profile_profile_test.html')
    assert(File.exists?(file_path))
  end
end
