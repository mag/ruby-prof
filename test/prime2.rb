require 'prime3'

# Need to use wall time for this test due to the sleep calls
RubyProf::measure_mode = RubyProf::WALL_TIME

def find_primes(arr)
  result = arr.select do |value|
    is_prime(value)
  end
  result
end

def find_largest(primes)
  largest = primes.first

  # Intentionally use upto for example purposes
  # (upto is also called from is_prime)
  0.upto(primes.length-1) do |i|
    sleep(0.02)
    prime = primes[i]
    if prime > largest
      largest = prime
    end
  end
  largest
end
