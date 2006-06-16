require "prof"

case ENV["RUBY_PROF_CLOCK_MODE"]
when "gettimeofday"
  Prof.clock_mode = Prof::GETTIMEOFDAY
  $stderr.puts("use gettimeofday(2) for profiling") if $VERBOSE
when "cpu"
  if ENV.key?("RUBY_PROF_CPU_FREQUENCY")
    Prof.cpu_frequency = ENV["RUBY_PROF_CPU_FREQUENCY"].to_f
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
  Prof.clock_mode = Prof::CPU
  $stderr.puts("use CPU clock counter for profiling") if $VERBOSE
else
  Prof.clock_mode = Prof::CLOCK
  $stderr.puts("use clock(3) for profiling") if $VERBOSE
end

at_exit {
  result = Prof.stop
  total = result.detect { |i|
    i.method_class.nil? && i.method_id == :"#toplevel"
  }.total_time
  if total == 0.0
    total = 0.001
  end
  sum = 0
  STDERR.print("  %%   cumulative   self              self     total\n")
  STDERR.print(" time   seconds   seconds    calls  ms/call  ms/call  name\n")
  for r in result
    sum += r.self_time
    if r.method_class.nil?
      name = r.method_id.to_s
    elsif r.method_class.is_a?(Class)
      name = r.method_class.to_s + "#" + r.method_id.to_s
    else
      name = r.method_class.to_s + "." + r.method_id.to_s
    end
    STDERR.printf("%6.2f %8.3f  %8.3f %8d %8.2f %8.2f  %s\n",
                  r.self_time / total * 100, sum, r.self_time, r.count,
                  r.self_time * 1000 / r.count, r.total_time * 1000 / r.count,
                  name)
  end
}
Prof.start
