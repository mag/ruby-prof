# file ts_dbaccess.rb
require 'test/unit'
require 'basic_test'
require 'duplicate_names_test'
require 'measure_mode_test'
require 'module_test'
require 'no_method_class_test'
require 'prime_test'
require 'printers_test'
require 'recursive_test'
require 'singleton_test'
require 'thread_test'
require 'timing_test'

# Can't use this one here cause it breaks
# the rest of the unit tets (Ruby Prof gets
# started twice).
#require 'profile_unit_test'
