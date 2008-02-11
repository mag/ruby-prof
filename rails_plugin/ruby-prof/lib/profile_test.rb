# Get the current environment
env = ENV["RAILS_ENV"]

# Load Rails testing infrastructure
require 'test_help'

# Now we can load test_helper since at this point 
# we've already loaded RAILS the requires at the
# top of test_helper will be ignored
require File.expand_path(File.join(RAILS_ROOT, 'test', 'test_helper'))

# Reset the current environment back to whatever it was 
# since teset_helper would have reset it to test
ENV["RAILS_ENV"] = env

# Now load ruby-prof and away we go
require 'ruby-prof'

module ActionController #:nodoc:
  class ProfileTest < ActionController::IntegrationTest
    DEFAULT_OPTIONS = {:measure_mode => RubyProf::PROCESS_TIME,
                       :times => 10,
                       :printer => RubyProf::FlatPrinter,
                       :min_percent => 5,
                       :output_dir => File.expand_path(File.join(RAILS_ROOT, 'tmp'))}
    
    def execute(method, url, count = 1)
      count.times do |i|
        print i % 10 == 0 ? 'x' : '.'
  
        STDOUT.flush
        send(method, url)
      end
      STDOUT << "\n"
    end
    
    def profile(method, url, options = {})
      options = DEFAULT_OPTIONS.merge(options)

      # Warmup
      puts "******* #{method_name} *******"
      puts "Warm up:"
      
      bench = Benchmark.realtime do
        self.execute(method, url)
      end
      print "%.2f seconds\n\n" % bench
      
      # Now run
      puts "Running:"
      RubyProf.measure_mode = options[:measure_mode]
      
      GC.disable
      result = RubyProf.profile do 
        self.execute(method, url, options[:times])                              
      end
      GC.enable
      
      bench = result.threads.values.inject(0) do |total, method_infos|
        top = method_infos.sort.last
        total += top.total_time
        total
      end
      puts "%.2f seconds\n\n" % bench
      result
    end

    def report_name(printer, options)
      # The report name is:
      #   test_name + measure_mode + report_type
      output_dir = options[:output_dir]
      
      path = case RubyProf.measure_mode
        when RubyProf::PROCESS_TIME
          File.join(output_dir, "#{method_name}_process")       
        when RubyProf::WALL_TIME
          File.join(output_dir, "#{method_name}_wall")       
        when RubyProf::MEMORY
          File.join(output_dir, "#{method_name}_memory")       
        when RubyProf::ALLOCATIONS
          File.join(output_dir, "#{method_name}_allocations")
      end
          
      case printer
        when RubyProf::FlatPrinter
          path += "_flat.txt"       
        when RubyProf::GraphPrinter
          path += "_graph.txt"       
        when RubyProf::GraphHtmlPrinter
          path += "_graph.html"       
        when RubyProf::CallTreePrinter
          path += "_tree.txt"
        else
          raise(RuntimeError, "Unknown printer class: ", printer)
      end
    end
    
    def report(result, options)
      # Setup options
      options = DEFAULT_OPTIONS.merge(options)
      
      # Create a printer
      printer = options[:printer].new(result)
      
      # Open the file
      file_name = report_name(printer, options)
      
      File.open(file_name, 'wb') do |file|
        printer.print(file, options)
      end
      result
    end
  end
end