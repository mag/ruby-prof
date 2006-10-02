
def make_random_array(length, maxnum)
	result = Array.new(length)
	result.each_index do |i|
		result[i] = rand(maxnum)
	end
		
	result
end
 
def is_prime(x)
	y = 2
	y.upto(x-1) do |i|
		return false if (x % i) == 0
	end
	true
end
