require 'prime2'
require 'prime3'

def run_primes
  length = 500	
  maxnum = 10000
  
  # Create random numbers
  random_array = make_random_array(length, maxnum)
  
  # Find the primes
  primes = find_primes(random_array)
  
  # Find the largest primes
  largest = find_largest(primes)
  #puts "largest is #{largest}"
end
