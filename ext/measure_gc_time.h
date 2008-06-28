#if defined(HAVE_RB_GC_TIME)
#define MEASURE_GC_TIME 6

static prof_measure_t
measure_gc_time()
{
#if HAVE_LONG_LONG
    return NUM2LL(rb_gc_time());
#else
    return NUM2LONG(rb_gc_time());
#endif
}

static double
convert_gc_time(prof_measure_t c)
{
    return (double) c / 1000000;
}

/* Document-method: prof_measure_gc_time
   call-seq:
     gc_time -> Integer

Returns the time spent doing garbage collections in microseconds.*/
static VALUE
prof_measure_gc_time(VALUE self)
{
    return rb_gc_time();
}

#endif
