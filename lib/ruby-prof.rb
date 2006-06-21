require "ruby_prof.so"

require "ruby-prof/flat_printer"
require "ruby-prof/graph_printer"
require "ruby-prof/graph_html_printer"

module RubyProf
  # See if the user specified the clock mode via 
  # the RUBY_PROF_CLOCK_MODE environment variable
  def self.figure_clock_mode
    case ENV["RUBY_PROF_CLOCK_MODE"]
	  when "wall" || "wall_time"
		  RubyProf.clock_mode = RubyProf::WALL_TIME
	  when "cpu" || "cpu_time"
  	  if ENV.key?("RUBY_PROF_CPU_FREQUENCY")
   		  RubyProf.cpu_frequency = ENV["RUBY_PROF_CPU_FREQUENCY"].to_f
  	  else
   		  begin
     		  open("/proc/cpuinfo") do |f|
       		  f.each_line do |line|
         		  s = line.slice(/cpu MHz\s*:\s*(.*)/, 1)
         		  if s
           		  RubyProf.cpu_frequency = s.to_f * 1000000
           		  break
         		  end
       		  end
     		  end
   		  rescue Errno::ENOENT
   		  end
  	  end
  	  RubyProf.clock_mode = RubyProf::CPU_TIME
	  else
  	  RubyProf.clock_mode = RubyProf::PROCESS_TIME
  	end
 	end
end

RubyProf::figure_clock_mode
