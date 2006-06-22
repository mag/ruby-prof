/*
 * $Id: prof.c 298 2005-05-11 08:33:37Z shugo $
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

#include <stdio.h>
#include <time.h>
#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif

#include <ruby.h>
#include <node.h>
#include <st.h>

#define PROF_VERSION "0.4.0"

static VALUE mProf;
static VALUE cResult;
static VALUE cMethodInfo;
static VALUE cCallInfo;

#ifdef HAVE_LONG_LONG
typedef LONG_LONG prof_clock_t;
#else
typedef unsigned long prof_clock_t;
#endif

typedef struct {
    VALUE klass;
    ID mid;
    int called;
    prof_clock_t self_time;
    prof_clock_t total_time;
} prof_call_info_t;

typedef struct {
    /* Cache hash value for speed reasons. */
    st_data_t key;
    VALUE klass;
    ID mid;
    int thread_id;
    int called;
    prof_clock_t self_time;
    prof_clock_t total_time;
    st_table *parents;
    st_table *children;
    /* Hack - piggyback a field to keep track of the
        of times the method appears in the current 
       stack.  Used to detect recursive cycles.  This
       works because there is an instance of this struct
       per method per thread.  Could have a separate
       hash table...would be cleaner but adds a bit of
       code and 1 extra lookup per event.*/
    int stack_count;
} prof_method_t;

typedef struct {
    /* Cache prof_method_t values to significantly 
       increase speed. */
    prof_method_t *method_info;
    prof_clock_t start_time;
    prof_clock_t child_cost;
} prof_data_t;

typedef struct {
    prof_data_t *start;
    prof_data_t *end;
    prof_data_t *ptr;
} prof_stack_t;

typedef struct {
    prof_stack_t* stack;
    st_table* minfo_table;
    int thread_id;
} thread_data_t;

typedef struct {
    VALUE threads;
} prof_result_t;

static VALUE toplevel_id;
static st_data_t toplevel_key;
static int clock_mode;
static st_table *threads_tbl = NULL;
static VALUE class_tbl = Qnil;

#define CLOCK_MODE_PROCESS 0
#define CLOCK_MODE_WALL 1
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
    return frequency;
}
#endif

static double
cpu_clock2sec(prof_clock_t c)
{
    return (double) c / cpu_frequency;
}

/* call-seq:
   cpu_frequency -> int

Returns the cpu's frequency.  This value is needed when using the 
cpu RubyProf::clock_mode. */
static VALUE
prof_get_cpu_frequency(VALUE self)
{
    return rb_float_new(cpu_frequency);
}

/* call-seq:
   cpu_frequency=value -> void

Sets the cpu's frequency.  This value is needed when using the 
cpu RubyProf::clock_mode. */
static VALUE
prof_set_cpu_freqeuncy(VALUE self, VALUE val)
{
    cpu_frequency = NUM2DBL(val);
    return val;
}

#endif

static prof_clock_t (*get_clock)() = clock_get_clock;
static double (*clock2sec)(prof_clock_t) = clock_clock2sec;


/* Helper method to get the id of a Ruby thread. */
static inline int
get_thread_id(VALUE thread)
{
    return NUM2INT(rb_obj_id(thread));
}

static VALUE
figure_singleton_name(VALUE klass)
{
    VALUE result = Qnil;

    /* We have come across a singleton object. First
       figure out what it is attached to.*/
    VALUE attached = rb_iv_get(klass, "__attached__");


    /* Is this a singleton class acting as a metaclass? */
    if (TYPE(attached) == T_CLASS)
    {
        result = rb_str_new2("<Class::");
        rb_str_append(result, rb_inspect(attached));
        rb_str_cat2(result, ">#");
    }

    /* Is this for singleton methods on a module? */
    else if (TYPE(attached) == T_MODULE)
    {
        result = rb_str_new2("<Module::");
        rb_str_append(result, rb_inspect(attached));
        rb_str_cat2(result, ">#");
    }

    /* Is it a regular singleton class for an object? */
    else if (TYPE(attached) == T_OBJECT)
    {
        /* Make sure to get the super class so that we don't
           mistakenly grab a T_ICLASS which would lead to
           unknown method errors. */
        VALUE super = rb_class_real(RCLASS(klass)->super);
        result = rb_str_new2("<Object::");
        rb_str_append(result, rb_inspect(super));
        rb_str_cat2(result, ">#");
    }
    else
    {
        /* Should never happen. */
        result = rb_str_new2("<Unknown:");
        rb_str_append(result, rb_inspect(klass));
        rb_str_cat2(result, ">#");
        rb_raise(rb_eRuntimeError, "Unknown singleton class: %i", result);
    }

    return result;
}

static VALUE
method_name(VALUE klass, ID mid)
{
    VALUE result;
    VALUE method_name;

    if (mid == ID_ALLOCATOR) 
        method_name = rb_str_new2("allocate");
    else
        method_name = rb_String(ID2SYM(mid));
    

    if (klass == Qnil)
        result = rb_str_new2("#");
    else if (TYPE(klass) == T_MODULE)
    {
        result = rb_inspect(klass);
        rb_str_cat2(result, "#");
    }
    else if (TYPE(klass) == T_CLASS && FL_TEST(klass, FL_SINGLETON))
    {
        result = figure_singleton_name(klass);
    }
    else if (TYPE(klass) == T_CLASS)
    {
        result = rb_inspect(klass);
        rb_str_cat2(result, "#");
    }
    else
    {
        /* Should never happen. */
        result = rb_str_new2("Unknown#");
        rb_str_append(result, rb_inspect(klass));
        rb_str_cat2(result, ">#");
        rb_raise(rb_eRuntimeError, "Unsupported type in method name: %i\n", result);
    }

    /* Last add in the method name */
    rb_str_append(result, method_name);

    return result;
}

static inline st_data_t
method_key(VALUE klass, ID mid)
{
    return klass ^ mid;
}


/* -- Stack to track methods call sequence and times ---- */
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


 
/* --- Keeps track of the methods the current method calls */
static st_table *
minfo_table_create()
{
    return st_init_numtable();
}

static inline int
minfo_table_insert(st_table *table, st_data_t key, prof_method_t *val)
{
    return st_insert(table, key, (st_data_t) val);
}

static inline prof_method_t *
minfo_table_lookup(st_table *table, st_data_t key)
{
    st_data_t val;
    if (st_lookup(table, key, &val)) {
	    return (prof_method_t *) val;
    }
    else {
	    return NULL;
    }
}

static void
minfo_table_free(st_table *table)
{
    st_free_table(table);
}


/* ---- Hash, keyed on class/method_id, that holds
        child call_info objects ---- */
static st_table *
child_table_create()
{
    return st_init_numtable();
}

static inline int
child_table_insert(st_table *table, st_data_t key, prof_call_info_t *val)
{
    return st_insert(table, key, (st_data_t) val);
}

static inline prof_call_info_t *
child_table_lookup(st_table *table, st_data_t key)
{
    st_data_t val;
    if (st_lookup(table, key, &val)) {
	    return (prof_call_info_t *) val;
    }
    else {
	    return NULL;
    }
}

static void
child_table_free(st_table *table)
{
    st_free_table(table);
}

/* Document-class: RubyProf::CallInfo
RubyProf::CallInfo is a helper class used by RubyProf::MethodInfo
to keep track of which child methods were called and how long
they took to execute. */

/* :nodoc: */
static prof_call_info_t *
call_info_create(VALUE klass, ID mid)
{
    prof_call_info_t *result;

    result = ALLOC(prof_call_info_t);
    result->klass = klass;
    result->mid = mid;
    result->called = 0;
    result->total_time = 0;
    result->self_time = 0;
    return result;
}

static void
call_info_free(prof_call_info_t *call_info)
{
    xfree(call_info);
}

static int
free_call_infos(st_data_t key, st_data_t value, st_data_t data)
{
    prof_call_info_t* call_info = (prof_call_info_t*) value;
    call_info_free(call_info);
    return ST_CONTINUE;
}

static VALUE
call_info_new(prof_call_info_t *result)
{
    /* We don't want Ruby freeing the underlying C structures, that
       is when the prof_method_t is freed. */
    return Data_Wrap_Struct(cCallInfo, NULL, NULL, result);
}

static prof_call_info_t *
get_call_info_result(VALUE obj)
{
    if (TYPE(obj) != T_DATA)
    {
        /* Should never happen */
	    rb_raise(rb_eTypeError, "Not a call info object");
    }
    return (prof_call_info_t *) DATA_PTR(obj);
}

/* call-seq:
   called -> int

Returns the total amount of time this method was called. */
static VALUE
call_info_called(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return INT2NUM(result->called);
}

/* call-seq:
   total_time -> float

Returns the total amount of time spent in this method and its children. */
static VALUE
call_info_total_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return rb_float_new(clock2sec(result->total_time));
}

/* call-seq:
   self_time -> float

Returns the total amount of time spent in this method. */
static VALUE
call_info_self_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return rb_float_new(clock2sec(result->self_time));
}

/* call-seq:
   children_time -> float

Returns the total amount of time spent in this method's children. */
static VALUE
call_info_children_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);
    prof_clock_t children_time = result->total_time - result->self_time;
    return rb_float_new(clock2sec(children_time));
}


/* Document-class: RubyProf::MethodInfo
The RubyProf::MethodInfo class stores profiling data for a method.
One instance of the RubyProf::MethodInfo class is created per method
called per thread.  Thus, if a method is called in two different
thread then there will be two RubyProf::MethodInfo objects
created.  RubyProf::MethodInfo objects can be accessed via
the RubyProf::Result object.
*/

/* :nodoc: */
static prof_method_t *
prof_method_create(VALUE klass, ID mid, VALUE thread)
{
    prof_method_t *result;

    /* Store reference to klass so it is not garbage collected */
    rb_hash_aset(class_tbl, klass, Qnil);

    result = ALLOC(prof_method_t);
    result->key = method_key(klass, mid);
    result->called = 0;
    result->total_time = 0;
    result->self_time = 0;
    result->klass = klass;
    result->mid = mid;
    result->thread_id = get_thread_id(thread);
    result->parents = minfo_table_create();
    result->children = child_table_create();
    result->stack_count = 0;
    return result;
}

static void
prof_method_mark(prof_method_t *data)
{
    rb_gc_mark(data->klass);
}

static void
prof_method_free(prof_method_t *data)
{
    st_foreach(data->children, free_call_infos, 0);
    minfo_table_free(data->parents);
    child_table_free(data->children);
    xfree(data);
}

static VALUE
prof_method_new(prof_method_t *result)
{
    return Data_Wrap_Struct(cMethodInfo, prof_method_mark, prof_method_free,
			    result);
}

static prof_method_t *
get_prof_method(VALUE obj)
{
    if (TYPE(obj) != T_DATA ||
	    RDATA(obj)->dfree != (RUBY_DATA_FUNC) prof_method_free)
    {
	    /* Should never happen */
        rb_raise(rb_eTypeError, "wrong profile result");
    }
    return (prof_method_t *) DATA_PTR(obj);
}

/* call-seq:
   called -> int

Returns the number of times this method was called. */
static VALUE
prof_method_called(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return INT2NUM(result->called);
}


/* call-seq:
   total_time -> float

Returns the total amount of time spent in this method and its children. */
static VALUE
prof_method_total_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return rb_float_new(clock2sec(result->total_time));
}

/* call-seq:
   self_time -> float

Returns the total amount of time spent in this method. */
static VALUE
prof_method_self_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return rb_float_new(clock2sec(result->self_time));
}

/* call-seq:
   children_time -> float

Returns the total amount of time spent in this method's children. */
static VALUE
prof_method_children_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);
    prof_clock_t children_time = result->total_time - result->self_time;
    return rb_float_new(clock2sec(children_time));
}

/* call-seq:
   thread_id -> id

Returns the id of the thread that executed this method.*/
static VALUE
prof_thread_id(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return INT2FIX(result->thread_id);
}

/* call-seq:
   method_class -> klass

Returns the Ruby klass that owns this method. */
static VALUE
prof_method_class(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return result->klass;
}

/* call-seq:
   method_id -> ID

Returns the id of this method. */
static VALUE
prof_method_id(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return ID2SYM(result->mid);
}

/* call-seq:
   method_name -> string

Returns the name of this method in the format Object#method.  Singletons
methods will be returned in the format <Object::Object>#method.*/

static VALUE
prof_method_name(VALUE self)
{
    prof_method_t *method = get_prof_method(self);
    return method_name(method->klass, method->mid);
}
   
static int
prof_method_collect_parents(st_data_t key, st_data_t value, st_data_t parents)
{
    prof_method_t *parent = (prof_method_t *) value;

    rb_ary_push(parents, INT2FIX((int) parent));
    return ST_CONTINUE;
}


/* call-seq:
   parents -> hash

Returns a hash table that lists all the methods that called this
method (ie, parents). The hash table is keyed on method name and contains references
to RubyProf::MethodInfo objects.*/
static VALUE
prof_method_parents(VALUE self)
{
    VALUE result = rb_hash_new();
    VALUE parents = rb_ary_new();
    int len = 0;
    int i = 0;

    /* Get the list of parents */
    prof_method_t *child = get_prof_method(self);
    st_foreach(child->parents, prof_method_collect_parents, parents);

    /* Iterate over each parent */
    len = RARRAY(parents)->len;
    for(i = 0; i<len; i++)
    {
        prof_call_info_t *call_info;

        /* First get the parent */
        VALUE item = rb_ary_entry(parents, i);
        prof_method_t *parent = (prof_method_t *)(FIX2INT(item));
        
        /* Now get the call info */
        call_info = child_table_lookup(parent->children, child->key);
        
        if (call_info == NULL)
        {
           /* Should never happen */
            rb_raise(rb_eRuntimeError,
                    "Could not find parent call info object for %s",
                    method_name(child->klass, child->mid));
        }

        /* Create a new Ruby CallInfo object and store it into the hash
           keyed on the parent's name.  We use the parent's name because
           we want to see that printed out for parent records in
           a call graph. */
        rb_hash_aset(result, method_name(parent->klass, parent->mid),
                     call_info_new(call_info));
    }

    return result;
}


static int
prof_method_collect_children(st_data_t key, st_data_t value, st_data_t result)
{
    prof_call_info_t *call_info = (prof_call_info_t *) value;
    VALUE name = method_name(call_info->klass, call_info->mid);
    VALUE hash = (VALUE) result;

    /* Create a new Ruby CallInfo object and store it into the hash
       keyed on the parent's name.  We use the parent's name because
       we want to see that printed out for child records in
       a call graph. */
    rb_hash_aset(hash, name, call_info_new(call_info));
    return ST_CONTINUE;
}

/* call-seq:
   children -> hash

Returns a hash table that lists all the methods that this method 
called (ie, children).  The hash table is keyed on method name 
and contains references to RubyProf::CallInfo objects.*/
static VALUE
prof_method_children(VALUE self)
{
    /* Returns a hash table, keyed on method name, of call info
       objects for all methods that this method calls (children). */

    VALUE children = rb_hash_new();
    prof_method_t *result = get_prof_method(self);
    st_foreach(result->children, prof_method_collect_children, children);
    return children;
}

/* :nodoc: */
static VALUE
prof_method_cmp(VALUE self, VALUE other)
{
    /* For call graphs we want to sort methods by
       their total time, not self time. */
    prof_method_t *x = get_prof_method(self);
    prof_method_t *y = get_prof_method(other);

    /* Want toplevel to always be first */
    if (x->klass == Qnil && x->mid == toplevel_id)
    	return INT2FIX(1);
    else if (y->klass == Qnil && y->mid == toplevel_id)
    	return INT2FIX(-11);
    else if (x->total_time < y->total_time)
    	return INT2FIX(-1);
    else if (x->total_time == y->total_time)
    	return INT2FIX(0);
    else
		return INT2FIX(1);
}

static int
collect_methods(st_data_t key, st_data_t value, st_data_t result)
{
    prof_method_t *method = (prof_method_t *) value;
    VALUE hash = (VALUE) result;
    VALUE base_name = method_name(method->klass, method->mid);
    VALUE method_key = base_name;

    /* Sanity check.  If we have generated the same method name for another prof_method 
       then we will overrite a pre-existing MethodInfo object in the table.  
       That would leave the original one unreferenced, which means it will 
       be garbage collected which leads to segmentation faults.  */
    VALUE existing_value = rb_hash_aref(hash, method_key);
    
    int i = 1;
    while(existing_value != Qnil)
    {
        method_key = rb_str_dup(base_name);
        rb_str_cat2(method_key, "_");
        rb_str_concat(method_key, rb_inspect(INT2NUM(i)));
        existing_value = rb_hash_aref(hash, method_key);
        i++;
    }

    rb_hash_aset(hash, method_key, prof_method_new(method));

    return ST_CONTINUE;
}


/* ---- Keeps track of thread's stack and methods ---- */
static thread_data_t*
thread_data_create()
{
    thread_data_t* result = ALLOC(thread_data_t);
    result->stack = stack_create();
    result->minfo_table = minfo_table_create();
    return result;
}

static void
thread_data_free(thread_data_t* thread_data)
{
    stack_free(thread_data->stack);
    minfo_table_free(thread_data->minfo_table);
    xfree(thread_data);
}


/* ---- Hash, keyed on thread, that stores thread's stack
        and methods---- */

static st_table *
threads_table_create()
{
    return st_init_numtable();
}

static inline int
threads_table_insert(st_table *table, VALUE thread, thread_data_t *thread_data)
{
    /* Its too slow to key on the real thread id so just typecast thread instead. */
    return st_insert(table, (st_data_t ) thread, (st_data_t) thread_data);
}

static inline thread_data_t *
threads_table_lookup(st_table *table, VALUE thread)
{
    thread_data_t* result;
    st_data_t val;

    /* Its too slow to key on the real thread id so just typecast thread instead. */
    if (st_lookup(table, (st_data_t) thread, &val))
    {
	    result = (thread_data_t *) val;
    }
    else
    {
        prof_method_t *toplevel;
        result = thread_data_create();
        /* Store the real thread id here so it can be shown in the results. */
        result->thread_id = get_thread_id(thread);

        /* Add a toplevel method to the thread */
        toplevel = prof_method_create(Qnil, toplevel_id, thread);
        toplevel->called = 1;
        toplevel->total_time = 0;
        toplevel->self_time = 0;
        minfo_table_insert(result->minfo_table, toplevel->key, toplevel);

        /* Insert the table */
        threads_table_insert(threads_tbl, thread, result);
	}
    return result;
}

static void
threads_table_free(st_table *table)
{
    st_free_table(table);
}

static int
free_thread_data(st_data_t key, st_data_t value, st_data_t dummy)
{
    thread_data_free((thread_data_t*)value);
    return ST_CONTINUE;
}

static void
free_threads(st_table* thread_table)
{
    st_foreach(thread_table, free_thread_data, 0);
}

static int
collect_threads(st_data_t key, st_data_t value, st_data_t result)
{
    /* Although threads are keyed on an id, that is actually a 
       pointer to the VALUE object of the thread.  So its bogus.
       However, in thread_data is the real thread id stored
       as an int. */
    thread_data_t* thread_data = (thread_data_t*) value;
    VALUE threads_hash = (VALUE) result;
    VALUE minfo_hash = rb_hash_new();
    st_foreach(thread_data->minfo_table, collect_methods, minfo_hash);
    rb_hash_aset(threads_hash, INT2NUM(thread_data->thread_id), minfo_hash);

    return ST_CONTINUE;
}

static void
update_result(prof_method_t * parent, prof_method_t *child,
              prof_clock_t total_time, prof_clock_t self_time)
{
    /* Update child information on parent (ie, the method that
       called the current method) */
    prof_call_info_t *parent_call_info = child_table_lookup(parent->children, child->key);
    if (parent_call_info == NULL)
    {
        parent_call_info = call_info_create(child->klass, child->mid);
        child_table_insert(parent->children, child->key, parent_call_info);
    }

    parent_call_info->called++;
    parent_call_info->total_time += total_time;
    parent_call_info->self_time += self_time;

    /* Slight hack here - if the child is the top level method then we want
       to update its total time */
    if (parent->key == toplevel_key)
        parent->total_time += total_time;

    /* Update information about the child (ie, the current method) */
    child->called++;
    child->total_time += total_time;
    child->self_time += self_time;

    /* Store pointer to parent */
    if (minfo_table_lookup(child->parents, parent->key) == NULL)
        minfo_table_insert(child->parents, parent->key, parent);
}

static void
prof_event_hook(rb_event_t event, NODE *node, VALUE self, ID mid, VALUE klass)
{
    static int profiling = 0;
    VALUE thread;
    thread_data_t* thread_data;
    prof_data_t *data;
    
    if (profiling) return;

    /* Special case - skip any methods from the mProf 
       module, such as Prof.stop, since they clutter
       the results but are not important to the results. */
    if (self == mProf) return;

    /* Set flag showing we have started profiling */
    profiling++;

    /* Is this an include for a module?  If so get the actual
       module class since we want to combine all profiling
       results for that module. */
    if (BUILTIN_TYPE(klass) == T_ICLASS)
        klass = RBASIC(klass)->klass;
      
    /* // Debug Code
    {
        VALUE class_name = rb_String(klass);
        char* c_class_name = StringValuePtr(class_name);
        char* c_method_name = rb_id2name(mid);
        VALUE generated_name = method_name(klass, mid);
        char* c_generated_name = StringValuePtr(generated_name);
        printf("Event: %2d, Method: %s#%s\n", event, c_class_name, c_method_name);
    }*/

    thread = rb_thread_current();
    thread_data = threads_table_lookup(threads_tbl, thread);
  
    switch (event) {
    case RUBY_EVENT_CALL:
    case RUBY_EVENT_C_CALL:
    {
        st_data_t key = method_key(klass, mid);
        prof_method_t *child = minfo_table_lookup(thread_data->minfo_table, key);

	    if (child == NULL) {
		    child = prof_method_create(klass, mid, thread);
		    minfo_table_insert(thread_data->minfo_table, key, child);
	    }

        /* Increment count of number of times this child has been called on
           the current stack. */
        child->stack_count++;
    
        /* Push the data for this method onto our stack */
        data = stack_push(thread_data->stack);
        data->method_info = child;
	    data->start_time = get_clock();
	    data->child_cost = 0;

	    break;
    }
    case RUBY_EVENT_RETURN:
    case RUBY_EVENT_C_RETURN:
	{
        prof_data_t* caller;
	    prof_method_t *parent;
	    prof_method_t *child;
        prof_clock_t now = get_clock();
	    prof_clock_t total_time, self_time;

        /* Pop data for this method off the stack. */
	    data = stack_pop(thread_data->stack);

        if (data == NULL)
        {
            /* Can happen on exceptions.  The stack gets unwound without RubyProf.stop
               being called. */
            VALUE name = method_name(klass, mid);
            VALUE message = rb_str_new2("ruby-prof: An error occured when leaving the method %s.\n");
            rb_str_cat2(message, "   Perhaps an exception occured in the code being profiled?\n" );
            rb_warn(StringValuePtr(message), StringValuePtr(name));
                    
            return;
        }

        /* Update timing information. */
        total_time = now - data->start_time;
        self_time = total_time - data->child_cost;

        /* Okay, get the method that called this method (ie, parent) */
        caller = stack_peek(thread_data->stack);

	    if (caller == NULL)
        {
            /* We are at the top of the stack, so grab the toplevel method */
            parent = minfo_table_lookup(thread_data->minfo_table, toplevel_key);
        }
        else
        {
            caller->child_cost += total_time;
    	    parent = caller->method_info;
        }
        
        /* Decrement count of number of times this child has been called on
           the current stack. */
        child = data->method_info;
        child->stack_count--;

        /* If the stack count is greater than zero, then this
           method has been called recursively.  In that case set the total
           time to zero because it will be correctly set when we unwind
           the stack up.  If we don't do this, then the total time for the 
           method will be double counted per recursive call. */
        if (child->stack_count != 0)
            total_time = 0;

        update_result(parent, child, total_time, self_time);
	    break;
	}
    }
    profiling--;
}


/* ========  ProfResult ============== */

/* Document-class: RubyProf::Result
The RubyProf::Result class is used to store the results of a 
profiling run.  And instace of the class is returned from
the methods RubyProf#stop and RubyProf#profile.

RubyProf::Result has one field, called threads, which is a hash
table keyed on thread ID.  For each thread id, the hash table
stores another hash table that contains profiling information
for each method called during the threads execution.  That
hash table is keyed on method name and contains
RubyProf::MethodInfo objects. */


static void
prof_result_mark(prof_result_t *prof_result)
{
    VALUE threads = prof_result->threads;
    rb_gc_mark(threads);
}

static void
prof_result_free(prof_result_t *prof_result)
{
    prof_result->threads = Qnil;
    xfree(prof_result);
}

static VALUE
prof_result_new()
{
    prof_result_t *prof_result = ALLOC(prof_result_t);

    /* Wrap threads in Ruby regular Ruby hash table. */
    prof_result->threads = rb_hash_new();
    st_foreach(threads_tbl, collect_threads, prof_result->threads);

    return Data_Wrap_Struct(cResult, prof_result_mark, prof_result_free, prof_result);
}


static prof_result_t *
get_prof_result(VALUE obj)
{
    if (TYPE(obj) != T_DATA ||
	    RDATA(obj)->dfree != (RUBY_DATA_FUNC) prof_result_free)
    {
        /* Should never happen */
	    rb_raise(rb_eTypeError, "wrong result object");
    }
    return (prof_result_t *) DATA_PTR(obj);
}

/* call-seq:
   threads -> Hash

Returns a hash table keyed on thread ID.  For each thread id,
the hash table stores another hash table that contains profiling
information for each method called during the threads execution.
That hash table is keyed on method name and contains 
RubyProf::MethodInfo objects. */
static VALUE
prof_result_threads(VALUE self)
{
    prof_result_t *prof_result = get_prof_result(self);
    return prof_result->threads;
}


/* call-seq:
   thread_id = int
   toplevel(thread_id) -> RubyProf::MethodInfo

Returns the RubyProf::MethodInfo object that represents the root
calling method for this thread.  This method will always
be named #toplevel and contains the total amount of time spent
executing code in this thread. */
static VALUE
prof_result_toplevel(VALUE self, VALUE thread_id)
{
    prof_result_t *prof_result = get_prof_result(self);
    VALUE methods = rb_hash_aref(prof_result->threads, thread_id);
    VALUE key = method_name(Qnil, toplevel_id);
    VALUE result = rb_hash_aref(methods, key);

    if (result == Qnil)
    {
        /* Should never happen */
	    rb_raise(rb_eRuntimeError, "Could not find toplevel method information");
    }
    return result;
}


/* call-seq:
   clock_mode -> clock_mode
   
   Returns the current clock mode.  Valid values include:
   *RubyProf::PROCESS_TIME - Measure process time.  This is default.  It is implemented using the clock function in the C Runtime library.
   *RubyProf::WALL_TIME - Measure wall time using gettimeofday on Linx and GetLocalTime on Windows
   *RubyProf::CPU_TIME - Measure time using the CPU clock counter.  This mode is only supported on Pentium or PowerPC platforms. */
static VALUE
prof_get_clock_mode(VALUE self)
{
    return INT2NUM(clock_mode);
}

/* call-seq:
   clock_mode=value -> void
   
   Specifies the method ruby-prof uses to measure time.  Valid values include:
   *RubyProf::PROCESS_TIME - Measure process time.  This is default.  It is implemented using the clock function in the C Runtime library.
   *RubyProf::WALL_TIME - Measure wall time using gettimeofday on Linx and GetLocalTime on Windows
   *RubyProf::CPU_TIME - Measure time using the CPU clock counter.  This mode is only supported on Pentium or PowerPC platforms. */
static VALUE
prof_set_clock_mode(VALUE self, VALUE val)
{
    int mode = NUM2INT(val);

    if (threads_tbl)
    {
	    rb_raise(rb_eRuntimeError, "can't set clock_mode while profiling");
    }

    switch (mode) {
    case CLOCK_MODE_PROCESS:
    	get_clock = clock_get_clock;
	    clock2sec = clock_clock2sec;
    	break;
    case CLOCK_MODE_WALL:
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

/* =========  Profiling ============= */


/* call-seq:
   start -> void
   
   Starts recording profile data.*/
static VALUE
prof_start(VALUE self)
{
    toplevel_id = rb_intern("toplevel");
    toplevel_key = method_key(Qnil, toplevel_id);

    if (threads_tbl != NULL)
    {
        rb_raise(rb_eRuntimeError, "RubyProf.start was already called");
    }

    /* Setup globals */
    class_tbl = rb_hash_new();
    threads_tbl = threads_table_create();
    
    rb_add_event_hook(prof_event_hook,
        RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
        RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);

    return Qnil;
}


/* call-seq:
   stop -> RubyProf::Result

   Stops collecting profile data and returns a RubyProf::Result object. */
static VALUE
prof_stop(VALUE self)
{
    VALUE result = Qnil;

    if (threads_tbl == NULL)
    {
        rb_raise(rb_eRuntimeError, "RubyProf.start is not called yet");
    }

    /* Now unregister from event   */
    rb_remove_event_hook(prof_event_hook);

    /* Create the result */
    result = prof_result_new();

    /* Free threads table */
    free_threads(threads_tbl);
    threads_table_free(threads_tbl);
    threads_tbl = NULL;

    /* Free reference to class_tbl */
    class_tbl = Qnil;
    
    return result;
}


/* call-seq:
   profile {block} -> RubyProf::Result

Profiles the specified block and returns a RubyProf::Result object. */
static VALUE
prof_profile(VALUE self)
{
    if (!rb_block_given_p())
    {
        rb_raise(rb_eArgError, "A block must be provided to the profile method.");
    }

    prof_start(self);
    rb_yield(Qnil);
    return prof_stop(self);
}


#if defined(_WIN32)
__declspec(dllexport) 
#endif
void

Init_ruby_prof()
{
    mProf = rb_define_module("RubyProf");
    rb_define_const(mProf, "VERSION", rb_str_new2(PROF_VERSION));
    rb_define_module_function(mProf, "start", prof_start, 0);
    rb_define_module_function(mProf, "stop", prof_stop, 0);
    rb_define_module_function(mProf, "profile", prof_profile, 0);
    rb_define_singleton_method(mProf, "clock_mode", prof_get_clock_mode, 0);
    rb_define_singleton_method(mProf, "clock_mode=", prof_set_clock_mode, 1);
    rb_define_const(mProf, "PROCESS_TIME", INT2NUM(CLOCK_MODE_PROCESS));
    rb_define_const(mProf, "WALL_TIME", INT2NUM(CLOCK_MODE_WALL));
#ifdef CLOCK_MODE_CPU
    rb_define_const(mProf, "CPU_TIME", INT2NUM(CLOCK_MODE_CPU));
    rb_define_singleton_method(mProf, "cpu_frequency",
			       prof_get_cpu_frequency, 0);
    rb_define_singleton_method(mProf, "cpu_frequency=",
			       prof_set_cpu_freqeuncy, 1);
#endif

    cResult = rb_define_class_under(mProf, "Result", rb_cObject);
    rb_undef_method(CLASS_OF(cMethodInfo), "new");
    rb_define_method(cResult, "threads", prof_result_threads, 0);
    rb_define_method(cResult, "toplevel", prof_result_toplevel, 1);

    cMethodInfo = rb_define_class_under(mProf, "MethodInfo", rb_cObject);
    rb_include_module(cMethodInfo, rb_mComparable);
    rb_undef_method(CLASS_OF(cMethodInfo), "new");
    rb_define_method(cMethodInfo, "called", prof_method_called, 0);
    rb_define_method(cMethodInfo, "total_time", prof_method_total_time, 0);
    rb_define_method(cMethodInfo, "self_time", prof_method_self_time, 0);
    rb_define_method(cMethodInfo, "children_time", prof_method_children_time, 0);
    rb_define_method(cMethodInfo, "name", prof_method_name, 0);
    rb_define_method(cMethodInfo, "method_class", prof_method_class, 0);
    rb_define_method(cMethodInfo, "method_id", prof_method_id, 0);
    rb_define_method(cMethodInfo, "thread_id", prof_thread_id, 0);
    rb_define_method(cMethodInfo, "parents", prof_method_parents, 0);
    rb_define_method(cMethodInfo, "children", prof_method_children, 0);
    rb_define_method(cMethodInfo, "<=>", prof_method_cmp, 1);

    cCallInfo = rb_define_class_under(mProf, "CallInfo", rb_cObject);
    rb_undef_method(CLASS_OF(cCallInfo), "new");
    rb_define_method(cCallInfo, "called", call_info_called, 0);
    rb_define_method(cCallInfo, "total_time", call_info_total_time, 0);
    rb_define_method(cCallInfo, "self_time", call_info_self_time, 0);
    rb_define_method(cCallInfo, "children_time", call_info_children_time, 0);

    rb_global_variable(&class_tbl);
}

/* vim: set filetype=c ts=8 sw=4 noexpandtab : */
