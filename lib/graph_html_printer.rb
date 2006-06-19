require "erb"

module RubyProf
  # Generates graph[link:files/examples/graph_html.html] profile reports as html. 
  # To use the grap html printer:
  #
	# 	result = RubyProf.profile do
  #			[code to profile]
  #		end
  #
  # 	printer = RubyProf::GraphHtmlPrinter.new(result, 5)
  # 	printer.print(STDOUT, 0)
  #
  # The constructor takes two arguments.  The first is
  # a RubyProf::Result object generated from a profiling
  # run.  The second is the minimum %total (the methods 
  # total time divided by the overall total time) that
  # a method must take for it to be printed out in 
  # the report.  Use this parameter to eliminate methods
  # that are not important to the overall profiling results.
  
  class GraphHtmlPrinter
	  PERCENTAGE_WIDTH = 8
	  TIME_WIDTH = 10
	  CALL_WIDTH = 20
	
  	# Create a GraphPrinter.  Result is a RubyProf::Result	
  	# object generated from a profiling run.
    def initialize(result)
  	  @result = result
 	  end

  	# Print a graph html report to the provided output.
  	# 
  	# output - Any IO oject, including STDOUT or a file. 
  	# The default value is STDOUT.
  	# 
  	# min_percent - The minimum %total (the methods 
  	# total time divided by the overall total time) that
  	# a method must take for it to be printed out in 
  	# the report. Default value is 0.
 	  def print(output = STDOUT, min_percent = 0)
      @output = output
      @min_percent = min_percent
      
      _erbout = @output
      erb = ERB.new(template, nil, nil)
      @output << erb.result(binding)
    end

    # These methods should be private but then ERB doesn't
    # work.  Turn off RDOC though 
    #--
    def total_time(thread_id)
			toplevel = @result.toplevel(thread_id)
			total_time = toplevel.total_time
			total_time = 0.01 if total_time == 0
			return total_time
    end
   
    def total_percent(method)
      overall_time = self.total_time(method.thread_id)
      (method.total_time/overall_time) * 100
    end
    
    def self_percent(method)
      overall_time = self.total_time(method.thread_id)
			(method.self_time/overall_time) * 100
    end

    # Creates a link to a method.  Note that we do not create
    # links to methods which are under the min_perecent 
    # specified by the user, since they will not be
    # printed out.
		def create_link(thread_id, name)
      # Get method
      method = @result.threads[thread_id][name]
      
      if self.total_percent(method) < @min_percent
        # Just return name
        name
      else
        # Create link
        "<a href=\"##{link_name(thread_id, name)}\">#{name}</a>" 
			end
  	end
  	
		def link_name(thread_id, name)\
    	name.gsub(/[><#\.\?=:]/,"_") + "_" + thread_id.to_s
  	end
    
 	  def template
'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
  <style media="all" type="text/css">
    table {
	    border-collapse: collapse;
	    border: 1px solid #CCC;
	    font-family: Verdana, Arial, Helvetica, sans-serif;
	    font-size: 9pt;
	    line-height: normal;
    }

    th {
	    text-align: center;
	    border-top: 1px solid #FB7A31;
	    border-bottom: 1px solid #FB7A31;
	    background: #FFC;
	    padding: 0.3em;
	    border-left: 1px solid silver;
    }

		tr.break td {
		  border: 0;
	    border-top: 1px solid #FB7A31;
			padding: 0;
			margin: 0;
		}

    tr.method td {
			font-weight: bold;
    }

    td {
	    padding: 0.3em;
    }

    td:first-child {
	    width: 190px;
	    }

    td {
	    border-left: 1px solid #CCC;
	    text-align: center;
    }	
  </style>
	</head>
	<body>
		<h1>Profile Report</h1>
		<!-- Threads Table -->
		<table>
			<tr>
				<th>Thread ID</th>
				<th>Total Time</th>
			</tr>
			<% for thread_id, methods in @result.threads %>
			<tr>
				<td><a href="#<%= thread_id %>"><%= thread_id %></a></td>
				<td><%= @result.toplevel(thread_id).total_time %></td>
			</tr>
			<% end %>
		</table>

		<!-- Methods Tables -->
		<% for thread_id, methods in @result.threads %>
			<h2><a name="<%= thread_id %>">Thread <%= thread_id %></a></h2>

			<table>
				<tr>
					<th><%= sprintf("%#{PERCENTAGE_WIDTH}s", "%Total") %></th>
					<th><%= sprintf("%#{PERCENTAGE_WIDTH}s", "%Self") %></th>
					<th><%= sprintf("%#{TIME_WIDTH}s", "Total") %></th>
					<th><%= sprintf("%#{TIME_WIDTH}s", "Self") %></th>
					<th><%= sprintf("%#{TIME_WIDTH+2}s", "Children") %></th>
					<th><%= sprintf("%#{CALL_WIDTH}s", "Calls") %></th>
					<th>Name</th>
				</tr>

				<% methods = methods.values.sort.reverse %>
				<% for method in methods %>
					<% method_total_percent = self.total_percent(method) %>
					<% next if method_total_percent < @min_percent %>
					<% method_self_percent = self.self_percent(method) %>
					
						<!-- Parents -->
						<% for name, call_info in method.parents %> 
							<tr>
								<td>&nbsp;</td>
								<td>&nbsp;</td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.total_time) %></td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.self_time) %></td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.children_time) %></td>
								<% called = "#{call_info.called}/#{method.called}" %>
								<td><%= sprintf("%#{CALL_WIDTH}s", called) %></td>
								<td><%= create_link(thread_id, name) %></td>
							</tr>
						<% end %>

						<tr class="method">
							<td><%= sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", method_total_percent) %></td>
							<td><%= sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", method_self_percent) %></td>
							<td><%= sprintf("%#{TIME_WIDTH}.2f", method.total_time) %></td>
							<td><%= sprintf("%#{TIME_WIDTH}.2f", method.self_time) %></td>
							<td><%= sprintf("%#{TIME_WIDTH}.2f", method.children_time) %></td>
							<td><%= sprintf("%#{CALL_WIDTH}i", method.called) %></td>
							<td><a name="<%= link_name(thread_id, method.name) %>"><%= method.name %></a></td>
						</tr>

						<!-- Children -->
						<% for name, call_info in method.children %> 
							<% methods = @result.threads[thread_id] %>
							<% child = methods[name] %>

							<tr>
								<td>&nbsp;</td>
								<td>&nbsp;</td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.total_time) %></td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.self_time) %></td>
								<td><%= sprintf("%#{TIME_WIDTH}.2f", call_info.children_time) %></td>
								<% called = "#{call_info.called}/#{child.called}" %>
								<td><%= sprintf("%#{CALL_WIDTH}s", called) %></td>
								<td><%= create_link(thread_id, name) %></td>
							</tr>
						<% end %>
						<!-- Create divider row -->
						<tr class="break"><td colspan="7"></td></tr>
				<% end %>
			</table>
		<% end %>
	</body>
</html>'
		end
  end
end	

