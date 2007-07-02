module RubyProf
  # Generates flat[link:files/examples/flat_txt.html] profile reports as text. 
  # To use the flat printer:
  #
  #   result = RubyProf.profile do
  #     [code to profile]
  #   end
  #
  #   printer = RubyProf::FlatPrinter.new(result)
  #   printer.print(STDOUT, 0)
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
      @result.threads.each do |thread_id, methods|
        print_methods(thread_id, methods)
        @output << "\n" * 2
      end
    end
    
    def print_methods(thread_id, methods)
      # Get total time
      toplevel = methods.sort.last
      total_time = toplevel.total_time
      if total_time == 0
        total_time = 0.01
      end
      
      # Now sort methods by largest self time,
      # not total time like in other printouts
      methods = methods.sort do |m1, m2|
        m1.self_time <=> m2.self_time
      end.reverse
      
      @output << "Thread ID: " << thread_id << "\n"
      @output << "Total: " << total_time << "\n"
      @output << " %self  cumulative  total     self   children  calls self/call total/call  name\n"

      sum = 0    
      methods.each do |method|
        self_percent = (method.self_time / total_time) * 100
        next if self_percent < @min_percent
        
        sum += method.self_time
        @output.printf("%6.2f %8.2f  %8.2f %8.2f %8.2f %8d %8.2f %8.2f     %s\n",
                      method.self_time / total_time * 100, # %self
                      sum,                                 # cumulative
                      method.total_time,                   # total
                      method.self_time,                    # self
                      method.children_time,                # children
                      method.called,                       # calls
                      method.self_time  / method.called,   # self/call
                      method.total_time  / method.called,  # total/call
                      method.name)                         # name
      end
    end
  end
end 

