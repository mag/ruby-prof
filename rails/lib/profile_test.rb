# Now load ruby-prof and away we go
require 'ruby-prof'

module RubyProf
  module Test
    DEFAULT_OPTIONS = {:measure_mode => RubyProf::PROCESS_TIME,
                       :times => 10,
                       :printer => RubyProf::FlatPrinter,
                       :min_percent => 5,
                       :output_dir => File.expand_path(File.join(RAILS_ROOT, 'tmp'))}
    

    def self.included(base)
      base.class_eval do
        include InstanceMethods
        alias :run_without_profile :run
      end
    end
  
    module InstanceMethods
      def run(result)
        warmup(result)
        profile(result)
      end
    
      def warmup(result)
        # Warmup
        puts "******* #{method_name} *******"
        puts "Warm up:"
      
        bench = Benchmark.realtime do
          self.run_without_profile(result)
        end
        print "%.2f seconds\n\n" % bench
      end
    
      def profile(result)
        # Now run
        puts "Running:"
        RubyProf.measure_mode = options[:measure_mode]
      
        GC.disable
        result = RubyProf.profile do 
          count.times do |i|
            print i % 10 == 0 ? 'x' : '.'
  
            STDOUT.flush
            self.run_without_profile(result)
          end
          STDOUT << "\n"
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
end 