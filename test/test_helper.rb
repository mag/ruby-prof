def print_test_result(result)
	printer = RubyProf::FlatPrinter.new(result, 0)
	printer.print(STDOUT)
    
	STDOUT << "\n" * 2
    
	printer = RubyProf::GraphPrinter.new(result, 0)
	printer.print(STDOUT)
end

def check_parent_times(method)
	return if method.parents.length == 0 

	parents_self_time = method.parents.values.inject(0) do |sum, call_info|
		sum + call_info.self_time
	end
	assert_equal(method.self_time, parents_self_time, method.name)	
    
	parents_children_time = method.parents.values.inject(0) do |sum, call_info|
		sum + call_info.children_time
	end
	assert_equal(method.children_time, parents_children_time, method.name)
end
  
def check_parent_calls(method)
	return if method.parents.length == 0 

	parent_calls = method.parents.values.inject(0) do |sum, call_info|
		sum + call_info.called
	end
	assert_equal(method.called, parent_calls, method.name)	
end
  
def check_child_times(method)
	return if method.children.length == 0
    
	children_total_time = method.children.values.inject(0) do |sum, call_info|
		sum + call_info.total_time
	end
end
  


