module RubyProf

  # Generate profiling information in calltree format
  # for use by kcachegrind and similar tools.

  class CallTreePrinter
    @@conv_factor = 1000
    def initialize(result)
      @result = result
    end

    def print(output = STDOUT)
      @output = output
      
      # add a header - this information is somewhat arbitrary
      @output << "events: milliseconds\n"
      @output << "cmd: your ruby script\n\n"

      # we don't know any files right now so put in dummy information

      print_threads
    end

    def print_threads
      @result.threads.sort.each do |thread_id,methods|
	print_methods(thread_id,methods)
      end
    end

    def print_methods(thread_id,methods)
      last_sourcefile = nil
      methods.each do | pair| 
        method_name = pair[0]
        minfo = pair[1]
	# iterate through each method and print out the timings.
	sf = minfo.source_file
	if last_sourcefile == nil || (last_sourcefile != sf && sf != "toplevel")
	    last_sourcefile = sf
	    @output << "fl=#{last_sourcefile}\n"
	end

	@output << "fn=#{method_name}\n"
	# line number and the converted timings
	@output << "#{minfo.line_no} #{(minfo.self_time*@@conv_factor).to_int}\n"
	# output children timings
	minfo.children.keys.each do |childname|
	  child_minfo = methods[childname]
	  
	  # only output the foreign file name if it is different than
	  # the current source file.
	  if child_minfo.source_file != last_sourcefile
	    @output << "cfl=#{child_minfo.source_file}\n"
	  end
	  
	  @output << "cfn=#{childname}\n"
	  childData = minfo.children[childname]
	  @output << "calls=#{childData.called} #{child_minfo.called_line_no}\n"
	  # timings: note total time in child
	  @output << "#{child_minfo.line_no} #{(childData.total_time*@@conv_factor).to_int}\n"
	end
      end
    end #end print_methods
  end # end class
end # end packages

