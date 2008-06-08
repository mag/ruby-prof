require "mkmf"

if RUBY_VERSION >= "1.9"
  if RUBY_RELEASE_DATE < "2005-03-17"
    STDERR.print("Ruby version is too old\n")
    exit(1)
  end
elsif RUBY_VERSION >= "1.8"
  if RUBY_RELEASE_DATE < "2005-03-22"
    STDERR.print("Ruby version is too old\n")
    exit(1)
  end
else
  STDERR.print("Ruby version is too old\n")
  exit(1)
end

have_header("sys/times.h")
have_func("rb_os_allocated_objects")
have_func("rb_gc_allocated_size")
have_func("rb_gc_malloc_allocations")
have_func("rb_gc_malloc_allocated_size")
create_makefile("ruby_prof")
