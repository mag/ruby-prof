# Make sure to first load the libraries we will override
require 'test/unit'
require 'ruby-prof'

module Test
  module Unit
    class TestCase
      
      alias :run__profile__ :run
      
      def run(result, &block)
        test_name = @method_name.to_sym
        alias_test_name = (@method_name + '__profile__').to_sym
        
        self.class.class_eval("alias :#{alias_test_name} :#{test_name}")
                
        self.class.send(:define_method, test_name) do 
          # Run the profiler        
          RubyProf.start
          __send__(alias_test_name)
          result = RubyProf.stop
      
          create_output_directory
            
          # Get the result file name
          file_name = name.gsub(/\(/, '_').gsub(/\)/, '').underscore
          file_path = File.join(output_directory, file_name)
          file_path += file_extension
      
          # Create a printer
          printer = self.printer.new(result)
    
          # Write the results
          File.open(file_path, 'w') do |file|
            RubyProf.start
            printer.print(file, min_percent)
            r2 = RubyProf.stop
            File.open('c:/temp/output.html', 'w') do |file2|
              p2 = self.printer.new(r2)
              p2.print(file2)
            end
          end
        end
        
        self.run__profile__(result, &block)
      end
      
      # Add some additional methods
      def min_percent
        10
      end
      
      def output_directory
        File.join(File.expand_path(RAILS_ROOT),
                  'test', 'profile')
      end
    
      def create_output_directory
        if not File.exist?(output_directory)
          Dir.mkdir(output_directory)
        end
      end

      def file_extension
        if printer == RubyProf::GraphHtmlPrinter
          '.html'
        else
          '.txt'
        end
      end
    
      def printer
        RubyProf::GraphHtmlPrinter
      end
    end
  end
end