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
          file_name = name.gsub(/\(/, '_').gsub(/\)/, '')
          file_name = self.underscore(file_name)
          file_path = File.join(output_directory, file_name)
          file_path += file_extension
      
          # Create a printer
          printer = self.printer.new(result)
    
          # Write the results
          File.open(file_path, 'w') do |file|
            printer.print(file, min_percent)
          end
        end
        
        self.run__profile__(result, &block)
      end
      
      # Taken from rails
      def underscore(camel_cased_word)
        camel_cased_word.to_s.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
          gsub(/([a-z\d])([A-Z])/,'\1_\2').
          tr("-", "_").downcase
      end

      # Add some additional methods
      def min_percent
        1
      end
      
      def output_directory
        # Put results in subdirectory called profile
        File.join(Dir.getwd, 'profile')
      end
    
      def create_output_directory
        if not File.exist?(output_directory)
          Dir.mkdir(output_directory)
        end
      end

      def file_extension
        if printer == RubyProf::FlatPrinter
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