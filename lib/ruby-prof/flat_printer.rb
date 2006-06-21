module RubyProf
  # Generates flat[link:files/examples/flat_txt.html] profile reports as text. 
  # To use the flat printer:
  #
	# 	result = RubyProf.profile do
  #			[code to profile]
  #		end
  #
  # 	printer = RubyProf::FlatPrinter.new(result)
  # 	printer.print(STDOUT, 0)
  #
	class FlatPrinter
  	# Create a FlatPrinter.  Result is a RubyProf::Result	
  	# object generated from a profiling run.
    def initialize(result)
  	  @result = result
 	  end

  	# Print a flat profile report to the provided output.
  	# 
  	# output - Any IO oject, including STDOUT or a file. 
  	# The default value is STDOUT.
  	# 
  	# min_percent - The minimum %self (the methods 
  	# self time divided by the overall total time) that
  	# a method must take for it to be printed out in 
  	# the report. Default value is 0.
 	  def print(output = STDOUT, min_percent = 0)
  	  @min_percent = min_percent
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

