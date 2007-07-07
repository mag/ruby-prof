def print_results(result)
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
    
  STDOUT << "\n" * 2
    
  printer = RubyProf::GraphPrinter.new(result)
  printer.print(STDOUT)
end

def check_parent_times(method)
  return if method.parents.length == 0 

  parents_self_time = method.parents.inject(0) do |sum, call_info|
    sum + call_info.self_time + call_info.wait_time
  end

  assert_in_delta(method.self_time, parents_self_time, 0.01, method.full_name) 
    
  parents_children_time = method.parents.inject(0) do |sum, call_info|
    sum + call_info.children_time + call_info.wait_time
  end
  assert_in_delta(method.children_time, parents_children_time, 0.01, method.full_name)
end
  
def check_parent_calls(method)
  return if method.parents.length == 0 
  
  parent_calls = method.parents.inject(0) do |sum, call_info|
    sum + call_info.called
  end
  assert_equal(method.called, parent_calls, method.full_name)  
end
  
def check_child_times(method)
  return if method.children.length == 0
    
  children_total_time = method.children.inject(0) do |sum, call_info|
    sum + call_info.total_time
  end
  
  assert_in_delta(method.children_time, children_total_time, 0.01, method.full_name)
end
