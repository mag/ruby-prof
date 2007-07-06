require 'ruby-prof/abstract_printer'

module RubyProf
  # Generate profiling information in calltree format
  # for use by kcachegrind and similar tools.

  class CallTreePrinter  < AbstractPrinter
    @@conv_factor = 1000
    
    def print(output = STDOUT, options = {})
      @output = output
      setup_options(options)
      
      # add a header - this information is somewhat arbitrary
      @output << "events: milliseconds\n"
      @output << "cmd: your ruby script\n\n"

      # we don't know any files right now so put in dummy information

      print_threads
    end

    def print_threads
      @result.threads.each do |thread_id, methods|
        print_methods(thread_id ,methods)
      end
    end

    def print_methods(thread_id ,methods)
      last_sourcefile = nil
      methods.reverse_each do |method| 
        # iterate through each method and print out the timings.
        sf = method.source_file
        if last_sourcefile == nil || (last_sourcefile != sf && sf != "toplevel")
          last_sourcefile = sf
          @output << "fl=#{last_sourcefile}\n"
        end

        @output << "fn=#{method.name}\n"
        # line number and the converted timings
        @output << "#{method.line} #{(method.self_time * @@conv_factor).to_int}\n"
        # output children timings
        method.children.each do |callee|
          # only output the foreign file name if it is different than
          # the current source file.
          if callee.target.source_file != last_sourcefile
            @output << "cfl=#{callee.target.source_file}\n"
          end
          
          @output << "cfn=#{callee.target.name}\n"
          @output << "calls=#{callee.target.called} #{callee.line}\n"
          # timings: note total time in child
          @output << "#{callee.line} #{(callee.target.total_time * @@conv_factor).to_int}\n"
        end
      end
    end #end print_methods
  end # end class
end # end packages