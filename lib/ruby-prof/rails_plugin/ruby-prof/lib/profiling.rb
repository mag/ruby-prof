require 'ruby-prof'

module ActionController #:nodoc:
  # The ruby-prof module times the performance of actions and reports to the logger. If the Active Record
  # package has been included, a separate timing section for database calls will be added as well.
  module Profiling #:nodoc:
    def self.included(base)
      base.class_eval do
        alias_method_chain :perform_action, :profiling
      end
    end

    def perform_action_with_profiling
      if not logger or logger.level != Logger::DEBUG
        perform_action_without_profiling
      else
        result = RubyProf.profile do
          perform_action_without_profiling
        end
        
        output = StringIO.new
        output << " [#{complete_request_uri rescue "unknown"}]"
        
        printer = RubyProf::FlatPrinter.new(result)
        # Skip anything less than 1% - which is a lot of
        # stuff in Rails
        printer.print(output, 1)
        
        logger.info(output.string)
      end
    end
  end
end
