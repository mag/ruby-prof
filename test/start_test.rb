#!/usr/bin/env ruby

require 'test/unit'
require 'ruby-prof'


def start
  RubyProf.start
end

def wait_around
  sleep(2)
end

def stop
  RubyProf.stop
end

start
wait_around
result = stop

printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
