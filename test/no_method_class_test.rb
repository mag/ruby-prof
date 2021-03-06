#!/usr/bin/env ruby

require 'ruby-prof'

# Make sure this works with no class or method
result = RubyProf.profile do 
  sleep 1
end

method = result.threads.values.first.sort.last

if method.full_name != 'Global#[No method]'
  raise(RuntimeError, "Wrong method name.  Expected: Global#[No method].  Actual: #{method.full_name}")
end