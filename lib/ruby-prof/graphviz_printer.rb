require 'set'

require 'ruby-prof/abstract_printer'

module RubyProf
  # Generates graph[link:files/examples/graph.gif] profile reports using GraphViz. 
  # To use the graphviz printer:
  #
  #   result = RubyProf.profile do
  #     [code to profile]
  #   end
  #
  #   printer = RubyProf::GraphvizPrinter.new(result, 5)
  #   printer.print(STDOUT, 0)
  #
  # The constructor takes two arguments.  The first is
  # a RubyProf::Result object generated from a profiling
  # run.  The second is the minimum %total (the methods 
  # total time divided by the overall total time) that
  # a method must take for it to be printed out in 
  # the report.  Use this parameter to eliminate methods
  # that are not important to the overall profiling results.

  class GraphvizPrinter < AbstractPrinter
    PERCENTAGE_WIDTH = 8
    TIME_WIDTH = 10
    CALL_WIDTH = 17

    # Create a GraphvizPrinter.  Result is a RubyProf::Result  
    # object generated from a profiling run.
    def initialize(result)
      super(result)

      @dot_data = ''
      @indent = 0
      @node_id = 0
      @method_to_node = {}
      @node_to_method = {}
      @edges = {}

      @thread_times = Hash.new
      calculate_thread_times
    end

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
    
    # Print a graph report to the provided output.
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
      print_threads
    end

    private 
    def add(s)
      @dot_data << s
    end

    def add_indented(s)
      add(' ' * @indent + s)
    end

    def add_line(s='')
      add_indented(s + "\n")
    end

    def digraph
      add_line "digraph {"
      @indent += 2

      add_line "node [shape = rectangle];"

      yield

      @indent -= 2
      add_line "}"
    end

    def subgraph
      add_line "subgraph {"
      @indent += 2

      @edges.clear

      yield

      @node_to_method.each_pair do |node,method|
        add_line "node [label = \"#{method}\" ] #{node};"
      end
      add_line
      @edges.each_pair do |from,tos|
        tos.each do |to|
          add_line "#{from} -> #{to};"
        end
      end

      @indent -= 2
      add_line "}"
    end

    def print_threads
      digraph do
        # sort assumes that spawned threads have higher object_ids
        @result.threads.sort.each do |thread_id, methods|
          subgraph do
            print_methods(thread_id, methods)
          end
        end
      end

      STDERR.puts @dot_data
      open('/Users/nitay/code/os/ruby-prof/txt', 'w') do |f|
        f << @dot_data
      end

      @output << `echo '#{@dot_data}' | dot -Tgif 2>&1`
      @output.flush
    end

    def print_methods(thread_id, methods)
      # Sort methods from longest to shortest total time
      methods = methods.sort

      toplevel = methods.last
      total_time = toplevel.total_time
      if total_time == 0
        total_time = 0.01
      end

      print_heading(thread_id)

      # Print each method in total time order
      methods.reverse_each do |method|
        total_percentage = (method.total_time/total_time) * 100
        self_percentage = (method.self_time/total_time) * 100

        next if total_percentage < min_percent

        # @output << "-" * 80 << "\n"

      #   print_parents(thread_id, method)
      #     
      #   # 1 is for % sign
      #   @output << sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", total_percentage)
      #   @output << sprintf("%#{PERCENTAGE_WIDTH-1}.2f\%", self_percentage)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", method.total_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", method.self_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", method.wait_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", method.children_time)
      #   @output << sprintf("%#{CALL_WIDTH}i", method.called)
      #   @output << sprintf("     %s", method_name(method))
      #   if print_file
      #     @output << sprintf("  %s:%s", method.source_file, method.line)
      #   end          
      #   @output << "\n"

        print_children(method)

        # print_parents(method)
      end
    end

    def print_heading(thread_id)
      label = "Thread ID = #{thread_id}"
      label << "\\nTotal Time: #{@thread_times[thread_id]}"
      add_line "label = \"#{label}\";"

      # @output << "Thread ID: #{thread_id}\n"
      # @output << "Total Time: #{@thread_times[thread_id]}\n"
      # @output << "\n"
      # 
      # # 1 is for % sign
      # @output << sprintf("%#{PERCENTAGE_WIDTH}s", "%total")
      # @output << sprintf("%#{PERCENTAGE_WIDTH}s", "%self")
      # @output << sprintf("%#{TIME_WIDTH}s", "total")
      # @output << sprintf("%#{TIME_WIDTH}s", "self")
      # @output << sprintf("%#{TIME_WIDTH}s", "wait")
      # @output << sprintf("%#{TIME_WIDTH}s", "child")
      # @output << sprintf("%#{CALL_WIDTH}s", "calls")
      # @output << "   Name"
      # @output << "\n"
    end
    
    def print_parents(method)
      method.parents.inject(method) do |child,parent|
        child = child.target if child.is_a? CallInfo

        parent_node = method_to_node(parent.target.full_name)
        child_node = method_to_node(child.full_name)

        @edges[parent_node] ||= []
        @edges[parent_node] << child_node

        child
      end

      #   @output << " " * 2 * PERCENTAGE_WIDTH
      #   @output << sprintf("%#{TIME_WIDTH}.2f", caller.total_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", caller.self_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", caller.wait_time)
      #   @output << sprintf("%#{TIME_WIDTH}.2f", caller.children_time)
      #     
      #   call_called = "#{caller.called}/#{method.called}"
      #   @output << sprintf("%#{CALL_WIDTH}s", call_called)
      #   @output << sprintf("     %s", caller.target.full_name)
      #   @output << "\n"
      # end
    end

    def method_to_node(method)
      unless @method_to_node.has_key?(method)
        @method_to_node[method] = @node_id
        @node_to_method[@node_id] = method
        @node_id += 1
      end
      @method_to_node[method]
    end

    def print_children(method)
      method.children.inject(method) do |parent,child|
        parent = parent.target if parent.is_a? CallInfo

        parent_node = method_to_node(parent.full_name)
        child_node = method_to_node(child.target.full_name)

        @edges[parent_node] ||= []
        @edges[parent_node] << child_node

        child
      end

        # @output << " " * 2 * PERCENTAGE_WIDTH
        # 
        # @output << sprintf("%#{TIME_WIDTH}.2f", child.total_time)
        # @output << sprintf("%#{TIME_WIDTH}.2f", child.self_time)
        # @output << sprintf("%#{TIME_WIDTH}.2f", child.wait_time)
        # @output << sprintf("%#{TIME_WIDTH}.2f", child.children_time)
        #       
        # call_called = "#{child.called}/#{child.target.called}"
        # @output << sprintf("%#{CALL_WIDTH}s", call_called)
        # @output << sprintf("     %s", child.target.full_name)
        # @output << "\n"
    end
  end
end 

