/*
 * $Id: prof.c 301 2006-06-12 04:45:23Z shugo $
 * Copyright (C) 2005  Shugo Maeda <shugo@ruby-lang.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <time.h>
#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif

#include <ruby.h>
#include <node.h>
#include <st.h>

#define PROF_VERSION "0.3"

static VALUE cProfResult;

#ifdef HAVE_LONG_LONG
typedef LONG_LONG prof_clock_t;
#else
typedef unsigned long prof_clock_t;
#endif

typedef struct {
    prof_clock_t start_time;
    prof_clock_t child_cost;
} prof_data_t;

typedef struct {
    prof_data_t *start;
    prof_data_t *end;
    prof_data_t *ptr;
} prof_stack_t;

typedef struct {
    int count;
    prof_clock_t total_time;
    prof_clock_t self_time;
    VALUE klass;
    ID mid;
} prof_result_t;

static prof_stack_t *stack;
static VALUE profiling_thread;
static st_table *stack_tbl;
static st_table *result_tbl;
static VALUE class_tbl;
static prof_result_t *toplevel;
static int clock_mode;

#define CLOCK_MODE_CLOCK 0
#define CLOCK_MODE_GETTIMEOFDAY 1
#if defined(_WIN32) || (defined(__GNUC__) && (defined(__i386__) || defined(__powerpc__) || defined(__ppc__)))
#define CLOCK_MODE_CPU 2
static double cpu_frequency;
#endif

#define INITIAL_STACK_SIZE 8

static prof_clock_t
clock_get_clock()
{
    return clock();
}

static double
clock_clock2sec(prof_clock_t c)
{
    return (double) c / CLOCKS_PER_SEC;
}

static prof_clock_t
gettimeofday_get_clock()
{
    struct timeval tv;

    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000 + tv.tv_usec;
}

static double
gettimeofday_clock2sec(prof_clock_t c)
{
    return (double) c / 1000000;
}

#ifdef CLOCK_MODE_CPU


#if defined(__GNUC__)

static prof_clock_t
cpu_get_clock()
{
#if defined(__i386__)
    unsigned long long x;
    __asm__ __volatile__ ("rdtsc" : "=A" (x));
    return x;
#elif defined(__powerpc__) || defined(__ppc__)
    unsigned long long x, y;

    __asm__ __volatile__ ("\n\
1:	mftbu   %1\n\
	mftb    %L0\n\
	mftbu   %0\n\
	cmpw    %0,%1\n\
	bne-    1b"
	: "=r" (x), "=r" (y));
    return x;
#endif
}

#elif defined(_WIN32)

static prof_clock_t
cpu_get_clock()
{
    prof_clock_t cycles = 0;

    __asm
    {
        rdtsc
            mov DWORD PTR cycles, eax
            mov DWORD PTR [cycles + 4], edx
    }
    return cycles;
}

#endif


/* The _WIN32 check is needed for msys (and maybe cygwin?) */
#if defined(__GNUC__) && !defined(_WIN32)

double get_cpu_frequency()
{
    unsigned long long x, y;

    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 500000000;
    x = cpu_get_clock();
    nanosleep(&ts, NULL);
    y = cpu_get_clock();
    return (y - x) * 2;
}

#elif defined(_WIN32)

double get_cpu_frequency()
{
    unsigned long long x, y;
    double frequency;
    x = cpu_get_clock();
    /* Use the windows sleep function, not Ruby's */
    Sleep(500);
    y = cpu_get_clock();
    frequency = 2*(y-x);
    printf("clock speed: %f", frequency);
    return frequency;
}
#endif

static double
cpu_clock2sec(prof_clock_t c)
{
    return (double) c / cpu_frequency;
}

static VALUE
prof_get_cpu_frequency(VALUE self)
{
    return rb_float_new(cpu_frequency);
}

static VALUE
prof_set_cpu_freqeuncy(VALUE self, VALUE val)
{
    cpu_frequency = NUM2DBL(val);
    return val;
}

#endif

static prof_clock_t (*get_clock)() = clock_get_clock;
static double (*clock2sec)(prof_clock_t) = clock_clock2sec;

static prof_stack_t *
stack_create()
{
    prof_stack_t *stack;

    stack = ALLOC(prof_stack_t);
    stack->start = stack->ptr =
	ALLOC_N(prof_data_t, INITIAL_STACK_SIZE);
    stack->end = stack->start + INITIAL_STACK_SIZE;
    return stack;
}

static void
stack_free(prof_stack_t *stack)
{
    xfree(stack->start);
    xfree(stack);
}

static inline prof_data_t *
stack_push(prof_stack_t *stack)
{
    if (stack->ptr == stack->end) {
	int len, new_capa;

	len = stack->ptr - stack->start;
	new_capa = (stack->end - stack->start) * 2;
	REALLOC_N(stack->start, prof_data_t, new_capa);
	stack->ptr = stack->start + len;
	stack->end = stack->start + new_capa;
    }
    return stack->ptr++;
}

static inline prof_data_t *
stack_pop(prof_stack_t *stack)
{
    if (stack->ptr == stack->start)
	return NULL;
    else
	return --stack->ptr;
}

static inline prof_data_t *
stack_peek(prof_stack_t *stack)
{
    if (stack->ptr == stack->start)
	return NULL;
    else
	return stack->ptr - 1;
}

static int
value_cmp(VALUE x, VALUE y)
{
    return x != y;
}

static int
value_hash(VALUE v)
{
    return v;
}

static struct st_hash_type type_value_hash = {
    value_cmp,
    value_hash,
#if RUBY_VERSION_CODE >= 190
    st_nothing_key_free,
    st_nothing_key_clone
#endif
};

static st_table *
stack_table_create()
{
    return st_init_table(&type_value_hash);
}

static inline int
stack_table_insert(st_table *table, VALUE thread, prof_stack_t *stack)
{
    return st_insert(table, (st_data_t ) thread, (st_data_t) stack);
}

static inline prof_stack_t *
stack_table_lookup(st_table *table, VALUE thread)
{
    st_data_t val;

    if (st_lookup(table, (st_data_t) thread, &val)) {
	return (prof_stack_t *) val;
    }
    else {
	return NULL;
    }
}

typedef struct {
    VALUE klass;
    ID mid;
} minfo_t;

static int
minfo_cmp(minfo_t *x, minfo_t *y)
{
    return x->klass != y->klass || x->mid != y->mid;
}

static int
minfo_hash(minfo_t *m)
{
    return m->klass ^ m->mid;
}

static struct st_hash_type type_minfo_hash = {
    minfo_cmp,
    minfo_hash,
#if RUBY_VERSION_CODE >= 190
    st_nothing_key_free,
    st_nothing_key_clone
#endif
};

static st_table *
minfo_table_create()
{
    return st_init_table(&type_minfo_hash);
}

static inline int
minfo_table_insert(st_table *table, VALUE klass, ID mid, prof_result_t *val)
{
    minfo_t* key;

    key = ALLOC(minfo_t);
    key->klass = klass;
    key->mid = mid;
    return st_insert(table, (st_data_t ) key, (st_data_t) val);
}

static inline prof_result_t *
minfo_table_lookup(st_table *table, VALUE klass, ID mid)
{
    minfo_t key;
    st_data_t val;

    key.klass = klass;
    key.mid = mid;
    if (st_lookup(table, (st_data_t) &key, &val)) {
	return (prof_result_t *) val;
    }
    else {
	return NULL;
    }
}

static prof_result_t *
prof_result_create(VALUE klass, ID mid)
{
    prof_result_t *result;

    result = ALLOC(prof_result_t);
    result->count = 0;
    result->total_time = 0;
    result->self_time = 0;
    result->klass = klass;
    rb_hash_aset(class_tbl, klass, Qnil);
    result->mid = mid;
    return result;
}

static void
prof_result_mark(prof_result_t *data)
{
    rb_gc_mark(data->klass);
}

static void
prof_result_free(prof_result_t *data)
{
    xfree(data);
}

static VALUE
prof_result_new(prof_result_t *result)
{
    return Data_Wrap_Struct(cProfResult, prof_result_mark, prof_result_free,
			    result);
}

static prof_result_t *
get_prof_result(VALUE obj)
{
    if (TYPE(obj) != T_DATA ||
	RDATA(obj)->dfree != (RUBY_DATA_FUNC) prof_result_free) {
	rb_raise(rb_eTypeError, "wrong profile result");
    }
    return (prof_result_t *) DATA_PTR(obj);
}

static VALUE
prof_result_count(VALUE self)
{
    prof_result_t *result = get_prof_result(self);

    return INT2NUM(result->count);
}

static VALUE
prof_result_total_time(VALUE self)
{
    prof_result_t *result = get_prof_result(self);

    return rb_float_new(clock2sec(result->total_time));
}

static VALUE
prof_result_self_time(VALUE self)
{
    prof_result_t *result = get_prof_result(self);

    return rb_float_new(clock2sec(result->self_time));
}

static VALUE
prof_result_method_class(VALUE self)
{
    prof_result_t *result = get_prof_result(self);

    return result->klass;
}

static VALUE
prof_result_method_id(VALUE self)
{
    prof_result_t *result = get_prof_result(self);

    return ID2SYM(result->mid);
}

static VALUE
prof_result_cmp(VALUE self, VALUE other)
{
    prof_result_t *x = get_prof_result(self);
    prof_result_t *y = get_prof_result(other);

    if (x->self_time == y->self_time) {
	if (x->count == y->count) {
	    if (x->total_time == y->total_time)
		return INT2FIX(0);
	    else if (x->total_time < y->total_time)
		return INT2FIX(-1);
	    else
		return INT2FIX(1);
	}
	else if (x->count < y->count) {
	    return INT2FIX(-1);
	}
	else {
	    return INT2FIX(1);
	}
    }
    else if (x->self_time < y->self_time) {
	return INT2FIX(-1);
    }
    else {
	return INT2FIX(1);
    }
}

static void
prof_event_hook(rb_event_t event, NODE *node, VALUE self, ID mid, VALUE klass)
{
    prof_data_t *data;
    VALUE curr_thread;
    static int profiling = 0;

    if (mid == ID_ALLOCATOR) return;
    if (profiling) return;
    profiling++;
    curr_thread = rb_thread_current();
    if (curr_thread != profiling_thread) {
	stack = stack_table_lookup(stack_tbl, curr_thread);
	if (stack == NULL) {
	    stack = stack_create();
	    stack_push(stack);
	    stack_table_insert(stack_tbl, curr_thread, stack);
	}
	profiling_thread = curr_thread;
    }
    switch (event) {
    case RUBY_EVENT_CALL:
    case RUBY_EVENT_C_CALL:
	data = stack_push(stack);
	data->start_time = get_clock();
	data->child_cost = 0;
	break;
    case RUBY_EVENT_RETURN:
    case RUBY_EVENT_C_RETURN:
	{
	    prof_result_t *result;
	    prof_clock_t now, cost;
	    prof_data_t *parent;

	    now = get_clock();
	    data = stack_pop(stack);
	    if (data == NULL)
	        break;
	    if (!NIL_P(klass)) {
		if (TYPE(klass) == T_ICLASS) {
		    klass = RBASIC(klass)->klass;
		}
		else if (FL_TEST(klass, FL_SINGLETON)) {
		    klass = self;
		}
	    }
	    result = minfo_table_lookup(result_tbl, klass, mid);
	    if (result == NULL) {
		result = prof_result_create(klass, mid);
		minfo_table_insert(result_tbl, klass, mid, result);
	    }
	    result->count++;
	    cost = now - data->start_time;
	    result->total_time += cost;
	    result->self_time += cost - data->child_cost;

	    parent = stack_peek(stack);
	    if (parent != NULL)
		parent->child_cost += cost;
	}
	break;
    }
    profiling--;
}

static VALUE
prof_start(VALUE self)
{
    prof_clock_t now;

    if (stack_tbl) {
        rb_raise(rb_eRuntimeError, "Prof.start was already called");
    }
    stack_tbl = stack_table_create();
    class_tbl = rb_hash_new();
    profiling_thread = rb_thread_current();
    stack = stack_create();
    stack_table_insert(stack_tbl, profiling_thread, stack);
    result_tbl = minfo_table_create();

    now = get_clock();
    toplevel = prof_result_create(Qnil, rb_intern("#toplevel"));
    toplevel->count = 1;
    toplevel->total_time = now;
    toplevel->self_time = 0;

    rb_add_event_hook(prof_event_hook,
        RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
        RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);

    return Qnil;
}

static int
collect_result(st_data_t key, st_data_t value, st_data_t result_list)
{
    prof_result_t *result = (prof_result_t *) value;
    VALUE list = (VALUE) result_list;

    xfree((void *) key);
    rb_ary_push(list, prof_result_new(result));
    return ST_CONTINUE;
}

static int
free_stack(st_data_t key, st_data_t value, st_data_t data)
{
    stack_free((prof_stack_t *) value);
    return ST_CONTINUE;
}

static VALUE
prof_stop(VALUE self)
{
    VALUE result_list;
    prof_clock_t now;

    if (stack_tbl == NULL) {
        rb_raise(rb_eRuntimeError, "Prof.start is not called yet");
    }

    now = get_clock();
    stack_pop(stack); /* data for Prof.stop */
    toplevel->total_time = now - toplevel->total_time;

    st_foreach(stack_tbl, free_stack, 0);
    st_free_table(stack_tbl);
    stack_tbl = NULL;
    profiling_thread = Qnil;
    stack = NULL;
    rb_remove_event_hook(prof_event_hook);
    result_list = rb_ary_new();
    st_foreach(result_tbl, collect_result, result_list);
    st_free_table(result_tbl);
    result_tbl = NULL;
    rb_ary_push(result_list, prof_result_new(toplevel));
    class_tbl = Qnil;
    return rb_ary_reverse(rb_ary_sort(result_list));
}

static VALUE
prof_get_clock_mode(VALUE self)
{
    return INT2NUM(clock_mode);
}

static VALUE
prof_set_clock_mode(VALUE self, VALUE val)
{
    int mode = NUM2INT(val);

    if (stack) {
	rb_raise(rb_eRuntimeError, "can't set clock_mode while profiling");
    }
    switch (mode) {
    case CLOCK_MODE_CLOCK:
	get_clock = clock_get_clock;
	clock2sec = clock_clock2sec;
	break;
    case CLOCK_MODE_GETTIMEOFDAY:
	get_clock = gettimeofday_get_clock;
	clock2sec = gettimeofday_clock2sec;
	break;
#ifdef CLOCK_MODE_CPU
    case CLOCK_MODE_CPU:
	if (cpu_frequency == 0)
	    cpu_frequency = get_cpu_frequency();
	get_clock = cpu_get_clock;
	clock2sec = cpu_clock2sec;
	break;
#endif
    default:
	rb_raise(rb_eArgError, "invalid mode: %d", mode);
	break;
    }
    clock_mode = mode;
    return val;
}

#if defined(_WIN32)
__declspec(dllexport) 
#endif
void
Init_prof()
{
    VALUE mProf;

    mProf = rb_define_module("Prof");
    rb_define_const(mProf, "VERSION", rb_str_new2(PROF_VERSION));
    rb_define_module_function(mProf, "start", prof_start, 0);
    rb_define_module_function(mProf, "stop", prof_stop, 0);
    rb_define_singleton_method(mProf, "clock_mode", prof_get_clock_mode, 0);
    rb_define_singleton_method(mProf, "clock_mode=", prof_set_clock_mode, 1);
    rb_define_const(mProf, "CLOCK", INT2NUM(CLOCK_MODE_CLOCK));
    rb_define_const(mProf, "GETTIMEOFDAY", INT2NUM(CLOCK_MODE_GETTIMEOFDAY));
#ifdef CLOCK_MODE_CPU
    rb_define_const(mProf, "CPU", INT2NUM(CLOCK_MODE_CPU));
    rb_define_singleton_method(mProf, "cpu_frequency",
			       prof_get_cpu_frequency, 0);
    rb_define_singleton_method(mProf, "cpu_frequency=",
			       prof_set_cpu_freqeuncy, 1);
#endif

    cProfResult = rb_define_class_under(mProf, "Result", rb_cObject);
    rb_include_module(cProfResult, rb_mComparable);
    rb_undef_method(CLASS_OF(cProfResult), "new");
    rb_define_method(cProfResult, "count", prof_result_count, 0);
    rb_define_method(cProfResult, "total_time", prof_result_total_time, 0);
    rb_define_method(cProfResult, "self_time", prof_result_self_time, 0);
    rb_define_method(cProfResult, "method_class", prof_result_method_class, 0);
    rb_define_method(cProfResult, "method_id", prof_result_method_id, 0);
    rb_define_method(cProfResult, "<=>", prof_result_cmp, 1);

    class_tbl = Qnil;
    rb_global_variable(&class_tbl);
    profiling_thread = Qnil;
    rb_global_variable(&profiling_thread);
}

/* vim: set filetype=c ts=8 sw=4 noexpandtab : */
