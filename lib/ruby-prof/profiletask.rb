#!/usr/bin/env ruby

require 'rake'
require 'rake/tasklib'

module RubyProf

  # Create a profile task.  All of the options provided by
  # the Rake:TestTask are supported except the loader
  # which is set to ruby-prof.  For detailed information
  # please refer to the Rake:TestTask documentation.
  #
  # ruby-prof specific options include:
  #
  #		output_dir - For each file specified an output 
  #							   file with profile information will be
  #								 written to the output directory.
  #								 By default, the output directory is
  #								 called "profile" and is created underneath
  # 							 the current working directory.
  #
  # 	printer - Specifies the output printer.  Valid values include
  # 						:flat, :graph, and :graph_html.
  #
  #   min_percent - Methods that take less than the specified percent
  #								  will not be written out.
  #
  # Example:
  #   
  #   require 'ruby-prof/task'
  #   
  #   ruby-prof::RubyProfTask.new do |t|
  #     t.test_files = FileList['test/test*.rb']
  #			t.output_dir = "c:/temp"
  #		  t.printer = :graph
  #     t.min_percent = 10
  #   end
  #
  # If the task is invoked with a "test=filename" command line option,
  # then the list of test files will be overridden to include only the
  # filename specified on the command line.  This provides an easy way
  # to run just one test.
  #
  # If rake is invoked with a "options=options" command line option,
  # then the given options are passed to ruby-prof.
  #
  # If rake is invoked with a "ruby-profPATH=path/to/ruby-prof" command line option,
  # then the given ruby-prof executable will be used; otherwise the one in your
  # PATH will be used.
  #
  # Examples:
  #
  #   rake ruby-prof                           # profiles all unit tests
  #   rake ruby-prof TEST=just_one_file.rb     # profiles one unit test
  #   rake ruby-prof PATTERN=*.rb    					 # profiles all files
  
  class ProfileTask < Rake::TestTask
    attr_writer :output_dir 
    attr_writer :min_percent 
    attr_writer :printer
    
    def initialize(name=:profile)
      @name = name
      @libs = ["lib"]
      @pattern = nil
      @options = Array.new
      @test_files = nil
      @verbose = false
      @warning = false
      @loader = :ruby_prof
      @ruby_opts = []
      @output_dir =  File.join(Dir.getwd, "profile")
      @printer = :graph
      @min_percent = 0
      yield self if block_given?
      @pattern = 'test/test*.rb' if @pattern.nil? && @test_files.nil?
      define
    end
  
    # Create the tasks defined by this task lib.
    def define
      create_output_directory
      
      lib_path = @libs.join(File::PATH_SEPARATOR)
      desc "Profile" + (@name==:profile ? "" : " for #{@name}")
      
      task @name do
	 			@ruby_opts.unshift( "-I#{lib_path}" )
	 			@ruby_opts.unshift( "-w" ) if @warning
				@ruby_opts.push("-S ruby-prof")
				@ruby_opts.push("--printer #{@printer}")
				@ruby_opts.push("--min_percent #{@min_percent}")

        file_list.each do |file_path|	 
          run_script(file_path)
        end
    	end
      self
    end
    
    # Run script
    def run_script(script_path)
			run_code = ''
			RakeFileUtils.verbose(@verbose) do
				file_name = File.basename(script_path, File.extname(script_path))
				case @printer
					when :flat, :graph
						file_name += ".txt"
					when :graph_html
						file_name += ".html"
					else
						file_name += ".txt"
				end
	  			
				output_file_path = File.join(output_directory, file_name)
					
				command_line = @ruby_opts.join(" ") + 
				              " --file=" + output_file_path +
				              " " + script_path

				puts "ruby " + command_line	
				# We have to catch the exeption to continue on.  However,
				# the error message will have been output to STDERR
				# already by the time we get here so we don't have to
				# do that again
				begin
					ruby command_line
       	rescue
        end
        puts ""
        puts ""
			end
    end

    def output_directory
      File.expand_path(@output_dir)
    end
    
    def create_output_directory
      if not File.exist?(output_directory)
      	Dir.mkdir(output_directory)
      end
    end
    
    # Run script
    #def figure_printer
      #printer = nil
      #@options.each do |option|
        #match = option.match(/-p\s*=?(.*)/)
        #if match
        	#printer = match[1]
        #elsif match = option.match(/--printer\s*=?\s*(.*)/)
          #printer = match[1]
        #end
      #end
      
      #case printer
      	#when nil
          #printer = 'flat'
        #when 'flat', 'graph', 'graph_html'
          ## do nothing
        #else
          #printer = 'flat'
      #end
        
      #printer
    #end

    def option_list # :nodoc:
      ENV['TESTOPTS'] || @options.join(" ") || ""
    end
  end
end

