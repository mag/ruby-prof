require 'ruby-prof/abstract_printer'

module RubyProf
  # Generate profiling information in calltree format
  # for use by kcachegrind and similar tools.

  class CallTreePrinter  < AbstractPrinter
    def print(output = STDOUT, options = {})
      @output = output
      setup_options(options)
        
      # add a header - this information is somewhat arbitrary
      @output << "events: "
      case RubyProf.measure_mode
        when RubyProf::PROCESS_TIME
          @output << 'process_time'
        when RubyProf::WALL_TIME
          @output << 'wall_time'
        when RubyProf::CPU_TIME
          @output << 'cpu_time'
        when RubyProf::ALLOCATIONS
          @output << 'allocations'
      end
      @output << "\n\n"  

      print_threads
    end

    def print_threads
      @result.threads.each do |thread_id, methods|
        print_methods(thread_id ,methods)
      end
    end

    def convert(value)
      (value * 1000).round
    end

    def file(method)
      File.expand_path(method.source_file)
    end

    def name(method)
      "#{method.klass_name}::#{method.method_name}"
    end

    def print_methods(thread_id, methods)
      methods.reverse_each do |method| 
        # Print out the file and method name
        @output << "fl=#{file(method)}\n"
        @output << "fn=#{name(method)}\n"

        # Now print out the function line number and its self time
        @output << "#{method.line} #{convert(method.self_time)}\n"

        # Now print out all the children methods
        method.children.each do |callee|
          @output << "cfl=#{file(callee.target)}\n"
          @output << "cfn=#{name(callee.target)}\n"
          @output << "calls=#{callee.called} #{callee.line}\n"

          # Print out total times here!
          @output << "#{callee.line} #{convert(callee.total_time)}\n"
        end
      @output << "\n"
      end
    end #end print_methods
  end # end class
end # end packages
