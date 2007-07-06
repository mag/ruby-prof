require 'ruby-prof/abstract_printer'
require "erb"

module RubyProf
  # Generates graph[link:files/examples/graph_html.html] profile reports as html. 
  # To use the grap html printer:
  #
  #   result = RubyProf.profile do
  #     [code to profile]
  #   end
  #
  #   printer = RubyProf::GraphHtmlPrinter.new(result, 5)
  #   printer.print(STDOUT, 0)
  #
  # The constructor takes two arguments.  The first is
  # a RubyProf::Result object generated from a profiling
  # run.  The second is the minimum %total (the methods 
  # total time divided by the overall total time) that
  # a method must take for it to be printed out in 
  # the report.  Use this parameter to eliminate methods
  # that are not important to the overall profiling results.
  
  class GraphHtmlPrinter < AbstractPrinter
    PERCENTAGE_WIDTH = 8
    TIME_WIDTH = 10
    CALL_WIDTH = 20
  
    # Create a GraphPrinter.  Result is a RubyProf::Result  
    # object generated from a profiling run.
    def initialize(result)
      super(result)
      @thread_times = Hash.new
      calculate_thread_times
    end

    # Print a graph html report to the provided output.
    # 
    # output - Any IO oject, including STDOUT or a file. 
    # The default value is STDOUT.
    # 
    # options - Hash of print options.  See #setup_options 
    #           for more information.
    #
    def print(output = STDOUT, options = {})
      @output = output
      setup_options(options)
      
      _erbout = @output
      erb = ERB.new(template, nil, nil)
      @output << erb.result(binding)
    end

    # These methods should be private but then ERB doesn't
    # work.  Turn off RDOC though 
    #--
    def calculate_thread_times
      # Cache thread times since this is an expensive
      # operation with the required sorting      
      @result.threads.each do |thread_id, methods|
        top = methods.sort.last
        
        thread_time = 0.01
        thread_time = top.total_time if top.total_time > 0

        @thread_times[thread_id] = thread_time 
      end
    end
    
    def thread_time(thread_id)
      @thread_times[thread_id]
    end
   
    def total_percent(thread_id, method)
      overall_time = self.thread_time(thread_id)
      (method.total_time/overall_time) * 100
    end
    
    def self_percent(method)
      overall_time = self.thread_time(method.thread_id)
      (method.self_time/overall_time) * 100
    end

    # Creates a link to a method.  Note that we do not create
    # links to methods which are under the min_perecent 
    # specified by the user, since they will not be
    # printed out.
    def create_link(thread_id, method)
      if self.total_percent(thread_id, method) < min_percent
        # Just return name
        method.name
      else
        href = '#' + link_href(thread_id, method)
        "<a href=\"#{href}\">#{method.name}</a>" 
      end
    end
    
    def link_href(thread_id, method)
      method.name.gsub(/[><#\.\?=:]/,"_") + "_" + thread_id.to_s
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
        <td><%= thread_time(thread_id) %></td>
      </tr>
      <% end %>
    </table>

    <!-- Methods Tables -->
    <% for thread_id, methods in @result.threads
         total_time = thread_time(thread_id) %>
      <h2><a name="<%= thread_id %>">Thread <%= thread_id %></a></h2>

      <table>
        <tr>
          <th><%= sprintf("%#{PERCENTAGE_WIDTH}s", "%Total") %></th>
          <th><%= sprintf("%#{PERCENTAGE_WIDTH}s", "%Self") %></th>
          <th><%= sprintf("%#{TIME_WIDTH}s", "Total") %></th>
          <th><%= sprintf("%#{TIME_WIDTH}s", "Self") %></th>
          <th><%= sprintf("%#{TIME_WIDTH+2}s", "Child") %></th>
          <th><%= sprintf("%#{CALL_WIDTH}s", "Calls") %></th>
          <th>Name</th>
        </tr>

        <% methods.sort.reverse_each do |method|
            total_percentage = (method.total_time/total_time) * 100
            next if total_percentage < min_percent
            self_percentage = (method.self_time/total_time) * 100 %>
          
            <!-- Parents -->
            <% for caller in method.parents %> 
              <tr>
                <td>&nbsp;</td>
                <td>&nbsp;</td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", caller.total_time) %></td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", caller.self_time) %></td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", caller.children_time) %></td>
                <% called = "#{caller.called}/#{method.called}" %>
                <td><%= sprintf("%#{CALL_WIDTH}s", called) %></td>
                <td><%= create_link(thread_id, caller.target) %></td>
              </tr>
            <% end %>

            <tr class="method">
              <td><%= sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", total_percentage) %></td>
              <td><%= sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", self_percentage) %></td>
              <td><%= sprintf("%#{TIME_WIDTH}.2f", method.total_time) %></td>
              <td><%= sprintf("%#{TIME_WIDTH}.2f", method.self_time) %></td>
              <td><%= sprintf("%#{TIME_WIDTH}.2f", method.children_time) %></td>
              <td><%= sprintf("%#{CALL_WIDTH}i", method.called) %></td>
              <td><a name="<%= link_href(thread_id, method) %>"><%= method_name(method) %></a></td>
            </tr>

            <!-- Children -->
            <% for callee in method.children %> 
              <tr>
                <td>&nbsp;</td>
                <td>&nbsp;</td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", callee.total_time) %></td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", callee.self_time) %></td>
                <td><%= sprintf("%#{TIME_WIDTH}.2f", callee.children_time) %></td>
                <% called = "#{callee.called}/#{callee.target.called}" %>
                <td><%= sprintf("%#{CALL_WIDTH}s", called) %></td>
                <td><%= create_link(thread_id, callee.target) %></td>
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

