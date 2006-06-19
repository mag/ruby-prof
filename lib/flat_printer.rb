module RubyProf
  # Generates flat[link:files/examples/flat_txt.html] profile reports as text. 
  # To use the flat printer:
  #
	# 	result = RubyProf.profile do
  #			[code to profile]
  #		end
  #
  # 	printer = RubyProf::FlatPrinter.new(result, 5)
  # 	printer.print(STDOUT, 0)
  #
  # The constructor takes two arguments.  The first is
  # a RubyProf::Result object generated from a profiling
  # run.  The second is the minimum %self (the methods 
  # self time divided by the overall total time) that
  # a method must take for it to be printed out in 
  # the report.  Use this parameter to eliminate methods
  # that are not important to the overall profiling results.
	class FlatPrinter
  	# Create a FlatPrinter.  Result is a RubyProf::Result	
  	# object generated from a profiling run.  min_percent
  	# specifies the minimum %self (the methods 
  	# self time divided by the overall total time) that
  	# a method must take for it to be printed out in 
  	# the report. 
    def initialize(result, min_percent = 0)
  	  @result = result
  	  @min_percent = min_percent
 	  end

  	# Print a graph report to the provided output.  Output
  	# can be any IO oject, including STDOUT or a file.
 	  def print(output)
      @output = output
      print_threads
		end      
		
		private 
		
 	  def print_threads
      # sort assumes that spawned threads have higher object_ids
			@result.threads.sort.each do |thread_id, methods|
				print_methods(thread_id, methods)
				@output << "\n" * 2
			end
    end
    
    def print_methods(thread_id, methods)
      toplevel = @result.toplevel(thread_id)
      total_time = toplevel.total_time

      methods = methods.values.sort do |method1, method2|
        method1.self_time <=> method2.self_time
     	end
     	methods.reverse!
      
  	  sum = 0
  	  @output << "Thread ID: " << thread_id << "\n"
  	  @output << " %self  cumulative  total     self   children  calls self/call total/call  name\n"

  	  for method in methods
        self_percent = (method.self_time / total_time) * 100
        next if self_percent < @min_percent
        
    	  sum += method.self_time
    	  @output.printf("%6.2f %8.2f  %8.2f %8.2f %8.2f %8d %8.2f %8.2f     %s\n",
	                    method.self_time / total_time * 100, # %self
	                    sum,                                 # cumulative
	                    method.total_time,                   # total
	                    method.self_time,                    # self
	                    method.children_time,                # children
	                    method.called,                        # calls
  	                  method.self_time  / method.called,    # self/call
  	                  method.total_time  / method.called,   # total/call
    	                method.name)                         # name
  	  end
	  end
  end
end	

