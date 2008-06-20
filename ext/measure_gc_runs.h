#if defined(HAVE_RB_GC_COLLECTIONS)
#define MEASURE_GC_RUNS 5

static prof_measure_t
measure_gc_runs()
{
    return NUM2INT(rb_gc_collections());
}

static double
convert_gc_runs(prof_measure_t c)
{
    return c;
}

/* Document-method: prof_measure_gc_runs
   call-seq:
     gc_runs -> Integer

Returns the total number of garbage collections.*/
static VALUE
prof_measure_gc_runs(VALUE self)
{
    return rb_gc_collections();
}

#elif defined(HAVE_RB_GC_HEAP_INFO)
#define MEASURE_GC_RUNS 5

static prof_measure_t
measure_gc_runs()
{
  VALUE h = rb_gc_heap_info();
  return NUM2UINT(rb_hash_aget(h, rb_str_new2("num_gc_passes")));
}

static double
convert_gc_runs(prof_measure_t c)
{
    return c;
}

static VALUE
prof_measure_gc_runs(VALUE self)
{
  VALUE h = rb_gc_heap_info();
  return rb_hash_aget(h, rb_str_new2("num_gc_passes"));
}

#endif
