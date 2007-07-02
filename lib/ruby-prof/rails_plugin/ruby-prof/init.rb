require 'profiling'

ActionController::Base.class_eval do
  include ActionController::Profiling
end
