# Now load ruby-prof and away we go
require 'ruby-prof'

module RubyProf
  module Test
    PROFILE_OPTIONS = {:measure_mode => RubyProf::PROCESS_TIME,
                       :count => 10,
                       :printers => [RubyProf::FlatPrinter,
                                     RubyProf::GraphHtmlPrinter],
                       :min_percent => 5,
                       :output_dir => Dir.pwd}
    

    def self.included(base)
      base.class_eval do
        include InstanceMethods
      end
    end
  
    module InstanceMethods
      def run(result)
        yield(self.class::STARTED, name)
        @_result = result
        run_warmup
        data = run_profile
        report(data)
        result.add_run
        yield(self.class::FINISHED, name)
      end
      
      def run_test
        begin
          setup
          yield
        rescue AssertionFailedError => e
          add_failure(e.message, e.backtrace)
        rescue StandardError, ScriptError
          add_error($!)
        ensure
          begin
            teardown
          rescue AssertionFailedError => e
            add_failure(e.message, e.backtrace)
          rescue StandardError, ScriptError
            add_error($!)
          end
        end
      end
      
      def run_warmup
        # Warmup
        puts "******* #{method_name} *******"
        puts "Warm up:"
      
        bench = run_test do
          Benchmark.realtime do
            __send__(@method_name)
          end   
        end
        print "%.2f seconds\n\n" % bench
      end
    
      def run_profile
        # Now run
        puts "Running:"
        RubyProf.measure_mode = PROFILE_OPTIONS[:measure_mode]
        
        PROFILE_OPTIONS[:count].times do |i|
          run_test do 
            begin
              print i % 10 == 0 ? 'x' : '.'
              STDOUT.flush
              GC.disable
            
              RubyProf.resume do
                __send__(@method_name)
              end
            ensure
              GC.enable
            end                             
          end
        end                     
        STDOUT << "\n"
      
        data = RubyProf.stop
        bench = data.threads.values.inject(0) do |total, method_infos|
          top = method_infos.sort.last
          total += top.total_time
          total
        end
        puts "%.2f seconds\n\n" % bench
        data
      end

      def report(data)
        PROFILE_OPTIONS[:printers].each do |printer_klass|
          printer = printer_klass.new(data)
      
          # Open the file
          file_name = report_name(printer)
      
          File.open(file_name, 'wb') do |file|
            printer.print(file, PROFILE_OPTIONS)
          end
        end
      end
      
      def report_name(printer)
        # The report name is:
        #   test_name + measure_mode + report_type
        output_dir = PROFILE_OPTIONS[:output_dir]
      
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
    end
  end
end 