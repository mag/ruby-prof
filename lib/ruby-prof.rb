require "ruby_prof.so"

require "flat_printer"
require "graph_printer"
require "graph_html_printer"

module RubyProf
  def set_clock_mode(clock_mode)
    case clock_mode || ENV["RUBY_PROF_CLOCK_MODE"]
		  when "gettimeofday"
  		  RubyProf.clock_mode = RubyProf::GETTIMEOFDAY
  		  $stderr.puts("use gettimeofday(2) for profiling") if $VERBOSE
		  when "cpu"
  		  if ENV.key?("RUBY_PROF_CPU_FREQUENCY")
    		  RubyProf.cpu_frequency = ENV["RUBY_PROF_CPU_FREQUENCY"].to_f
  		  else
    		  begin
      		  open("/proc/cpuinfo") do |f|
        		  f.each_line do |line|
          		  s = line.slice(/cpu MHz\s*:\s*(.*)/, 1)
          		  if s
            		  Prof.cpu_frequency = s.to_f * 1000000
            		  break
          		  end
        		  end
      		  end
    		  rescue Errno::ENOENT
    		  end
  		  end
  		  RubyProf.clock_mode = RubyProf::CPU
  		  $stderr.puts("use CPU clock counter for profiling") if $VERBOSE
		  else
  		  RubyProf.clock_mode = RubyProf::CLOCK
  		  $stderr.puts("use clock(3) for profiling") if $VERBOSE
  	end
 	end
end	

