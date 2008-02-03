/*
 * Copyright (C) 2007  Shugo Maeda <shugo@ruby-lang.org>
 *                     Charlie Savage <cfis@savagexi.com>
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

/* ruby-prof tracks the time spent executing every method in ruby programming.
   The main players are:

     prof_result_t     - Its one field, values,  contains the overall results
     thread_data_t     - Stores data about a single thread.  
     prof_stack_t      - The method call stack in a particular thread
     prof_method_t     - Profiling information for each method
     prof_call_info_t  - Keeps track a method's callers and callees. 

  The final resulut is a hash table of thread_data_t, keyed on the thread
  id.  Each thread has an hash a table of prof_method_t, keyed on the
  method id.  A hash table is used for quick look up when doing a profile.
  However, it is exposed to Ruby as an array.
  
  Each prof_method_t has two hash tables, parent and children, of prof_call_info_t.
  These objects keep track of a method's callers (who called the method) and its
  callees (who the method called).  These are keyed the method id, but once again,
  are exposed to Ruby as arrays.  Each prof_call_into_t maintains a pointer to the
  caller or callee method, thereby making it easy to navigate through the call 
  hierarchy in ruby - which is very helpful for creating call graphs.      
*/


#include <stdio.h>

#include <ruby.h>
#ifndef RUBY_VM
#include <node.h>
#include <st.h>
typedef rb_event_t rb_event_flag_t;
#define rb_sourcefile() (node ? node->nd_file : 0)
#define rb_sourceline() (node ? nd_line(node) : 0)
#endif


/* ================  Constants  =================*/
#define INITIAL_STACK_SIZE 8
#define PROF_VERSION "0.6.0"


/* ================  Measurement  =================*/
#ifdef HAVE_LONG_LONG
typedef LONG_LONG prof_measure_t;
#else
typedef unsigned long prof_measure_t;
#endif

#include "measure_process_time.h"
#include "measure_wall_time.h"
#include "measure_cpu_time.h"
#include "measure_allocations.h"

static prof_measure_t (*get_measurement)() = measure_process_time;
static double (*convert_measurement)(prof_measure_t) = convert_process_time;

/* ================  DataTypes  =================*/
static VALUE mProf;
static VALUE cResult;
static VALUE cMethodInfo;
static VALUE cCallInfo;

/* Profiling information for each method. */
typedef struct prof_method_t {
    st_data_t key;              /* Cache hash value for speed reasons. */
    VALUE name;                 /* Name of the method. */
    VALUE klass;                /* The method's class. */
    ID mid;                     /* The method id. */
    int depth;                  /* The recursive depth this method was called at.*/
    int called;                 /* Number of times called */
    const char* source_file;    /* The method's source file */
    int line;                   /* The method's line number. */
    prof_measure_t total_time;  /* Total time spent in this method and children. */
    prof_measure_t self_time;   /* Total time spent in this method. */
    prof_measure_t wait_time;   /* Total time this method spent waiting for other threads. */
    st_table *parents;          /* The method's callers (prof_call_info_t). */
    st_table *children;         /* The method's callees (prof_call_info_t). */
    int active_frame;           /* # of active frames for this method.  Used to detect
                                   recursion.  Stashed here to avoid extra lookups in 
                                   the hook method - so a bit hackey. */
    struct prof_method_t *base;        /* For recursion - this is the parent method */
} prof_method_t;


/* Callers and callee information for a method. */
typedef struct {
    prof_method_t *target;
    int called;
    prof_measure_t total_time;
    prof_measure_t self_time;
    prof_measure_t wait_time;
    int line;  
} prof_call_info_t;


/* Temporary object that maintains profiling information
   for active methods - there is one per method.*/
typedef struct {
    /* Caching prof_method_t values significantly
       increases performance. */
    prof_method_t *method;
    prof_measure_t start_time;
    prof_measure_t wait_time;
    prof_measure_t child_time;
    unsigned int line;
} prof_frame_t;

/* Current stack of active methods.*/
typedef struct {
    prof_frame_t *start;
    prof_frame_t *end;
    prof_frame_t *ptr;
} prof_stack_t;

/* Profiling information for a thread. */
typedef struct {
    unsigned long thread_id;                  /* Thread id */
    st_table* method_info_table;     /* All called methods */
    prof_stack_t* stack;             /* Active methods */
    prof_measure_t last_switch;      /* Point of last context switch */
} thread_data_t;

typedef struct {
    VALUE threads;
} prof_result_t;


/* ================  Variables  =================*/
static int measure_mode;
static st_table *threads_tbl = NULL;
/* TODO - If Ruby become multi-threaded this has to turn into
   a separate stack since this isn't thread safe! */
static thread_data_t* last_thread_data = NULL;


/* ================  Helper Functions  =================*/
/* Helper method to get the id of a Ruby thread. */
static inline long
get_thread_id(VALUE thread)
{
    //return NUM2ULONG(rb_obj_id(thread));
    // From line 1997 in gc.c
    return (long)thread;
}

static VALUE
figure_singleton_name(VALUE klass)
{
    VALUE result = Qnil;

    /* We have come across a singleton object. First
       figure out what it is attached to.*/
    VALUE attached = rb_iv_get(klass, "__attached__");

    /* Is this a singleton class acting as a metaclass? */
    if (BUILTIN_TYPE(attached) == T_CLASS)
    {
        result = rb_str_new2("<Class::");
        rb_str_append(result, rb_inspect(attached));
        rb_str_cat2(result, ">");
    }

    /* Is this for singleton methods on a module? */
    else if (BUILTIN_TYPE(attached) == T_MODULE)
    {
        result = rb_str_new2("<Module::");
        rb_str_append(result, rb_inspect(attached));
        rb_str_cat2(result, ">");
    }

    /* Is this for singleton methods on an object? */
    else if (BUILTIN_TYPE(attached) == T_OBJECT)
    {
        /* Make sure to get the super class so that we don't
           mistakenly grab a T_ICLASS which would lead to
           unknown method errors. */
#ifdef RCLASS_SUPER
        VALUE super = rb_class_real(RCLASS_SUPER(klass));
#else
        VALUE super = rb_class_real(RCLASS(klass)->super);
#endif
        result = rb_str_new2("<Object::");
        rb_str_append(result, rb_inspect(super));
        rb_str_cat2(result, ">");
    }
    
    /* Ok, this could be other things like an array made put onto
       a singleton object (yeah, it happens, see the singleton
       objects test case). */
    else
    {
        result = rb_inspect(klass);
    }

    return result;
}

static VALUE
klass_name(VALUE klass)
{
    VALUE result = Qnil;
    
    if (klass == 0 || klass == Qnil)
    {
        result = rb_str_new2("Global");
    }
    else if (BUILTIN_TYPE(klass) == T_MODULE)
    {
        result = rb_inspect(klass);
    }
    else if (BUILTIN_TYPE(klass) == T_CLASS && FL_TEST(klass, FL_SINGLETON))
    {
        result = figure_singleton_name(klass);
    }
    else if (BUILTIN_TYPE(klass) == T_CLASS)
    {
        result = rb_inspect(klass);
    }
    else
    {
        /* Should never happen. */
        result = rb_str_new2("Unknown");
    }

    return result;
}

static VALUE
method_name(ID mid, int depth)
{
    VALUE result;

    if (mid == ID_ALLOCATOR) 
        result = rb_str_new2("allocate");
    else if (mid == 0)
        result = rb_str_new2("[No method]");
    else
        result = rb_String(ID2SYM(mid));
    
    if (depth > 0)
    {
      char buffer[65];
      sprintf(buffer, "%i", depth);
      rb_str_cat2(result, "-");
      rb_str_cat2(result, buffer);
    }

    return result;
}

static VALUE
full_name(VALUE klass, ID mid, int depth)
{
  VALUE result = klass_name(klass);
  rb_str_cat2(result, "#");
  rb_str_append(result, method_name(mid, depth));
  
  return result;
}


static inline st_data_t
method_key(VALUE klass, ID mid, int depth)
{
  /* No idea if this is a unique key or not.  Would be
     best to use the method name, but we can't, since
     that calls internal ruby functions which would
     cause the hook method to recursively call itself.
     And that is too much of a bother to deal with.
     Plus of course, this is faster. */
  return (klass * 100) + (mid * 10) + depth;
}

/* ================  Stack Handling   =================*/

/* Creates a stack of prof_frame_t to keep track
   of timings for active methods. */
static prof_stack_t *
stack_create()
{
    prof_stack_t *stack = ALLOC(prof_stack_t);
    stack->start = ALLOC_N(prof_frame_t, INITIAL_STACK_SIZE);
    stack->ptr = stack->start;
    stack->end = stack->start + INITIAL_STACK_SIZE;
    return stack;
}

static void
stack_free(prof_stack_t *stack)
{
    xfree(stack->start);
    xfree(stack);
}

static inline prof_frame_t *
stack_push(prof_stack_t *stack)
{
  /* Is there space on the stack?  If not, double
     its size. */
  if (stack->ptr == stack->end)
  {
    size_t len = stack->ptr - stack->start;
    size_t new_capacity = (stack->end - stack->start) * 2;
    REALLOC_N(stack->start, prof_frame_t, new_capacity);
    stack->ptr = stack->start + len;
    stack->end = stack->start + new_capacity;
  }
  return stack->ptr++;
}

static inline prof_frame_t *
stack_pop(prof_stack_t *stack)
{
    if (stack->ptr == stack->start)
      return NULL;
    else
      return --stack->ptr;
}

static inline prof_frame_t *
stack_peek(prof_stack_t *stack)
{
    if (stack->ptr == stack->start)
      return NULL;
    else
      return stack->ptr - 1;
}

static inline size_t
stack_size(prof_stack_t *stack)
{
    return stack->ptr - stack->start;
}

/* ================  Method Info Handling   =================*/
 
/* --- Keeps track of the methods the current method calls */
static st_table *
method_info_table_create()
{
    return st_init_numtable();
}

static inline size_t
method_info_table_insert(st_table *table, st_data_t key, prof_method_t *val)
{
    return st_insert(table, key, (st_data_t) val);
}

static inline prof_method_t *
method_info_table_lookup(st_table *table, st_data_t key)
{
    st_data_t val;
    if (st_lookup(table, key, &val))
    {
      return (prof_method_t *) val;
    }
    else 
    {
      return NULL;
    }
}


static void
method_info_table_free(st_table *table)
{
    /* Don't free the contents since they are wrapped by
       Ruby objects! */
    st_free_table(table);
}


/* ================  Call Info Handling   =================*/

/* ---- Hash, keyed on class/method_id, that holds call_info objects ---- */
static st_table *
caller_table_create()
{
    return st_init_numtable();
}

static inline size_t
caller_table_insert(st_table *table, st_data_t key, prof_call_info_t *val)
{
    return st_insert(table, key, (st_data_t) val);
}

static inline prof_call_info_t *
caller_table_lookup(st_table *table, st_data_t key)
{
    st_data_t val;
    if (st_lookup(table, key, &val))
    {
      return (prof_call_info_t *) val;
    }
    else
    {
      return NULL;
    }
}

static void
caller_table_free(st_table *table)
{
    st_free_table(table);
}

/* Document-class: RubyProf::CallInfo
RubyProf::CallInfo is a helper class used by RubyProf::MethodInfo
to keep track of which child methods were called and how long
they took to execute. */

/* :nodoc: */
static prof_call_info_t *
call_info_create(prof_method_t* method)
{
    prof_call_info_t *result;

    result = ALLOC(prof_call_info_t);
    result->target = method;
    result->called = 0;
    result->total_time = 0;
    result->self_time = 0;
    result->wait_time = 0;
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
       is done when the prof_method_t is freed. */
    return Data_Wrap_Struct(cCallInfo, NULL, NULL, result);
}

static prof_call_info_t *
get_call_info_result(VALUE obj)
{
    if (BUILTIN_TYPE(obj) != T_DATA)
    {
        /* Should never happen */
      rb_raise(rb_eTypeError, "Not a call info object");
    }
    return (prof_call_info_t *) DATA_PTR(obj);
}


/* call-seq:
   called -> MethodInfo

Returns the target method. */
static VALUE
call_info_target(VALUE self)
{
    /* Target is a pointer to a method_info - so we have to be careful
       about the GC.  We will wrap the method_info but provide no
       free method so the underlying object is not freed twice! */
    
    prof_call_info_t *result = get_call_info_result(self);
    return Data_Wrap_Struct(cMethodInfo, NULL, NULL, result->target);
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
   line_no -> int

   returns the line number of the method */
static VALUE
call_info_line(VALUE self)
{
    return rb_int_new(get_call_info_result(self)->line);
}

/* call-seq:
   total_time -> float

Returns the total amount of time spent in this method and its children. */
static VALUE
call_info_total_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return rb_float_new(convert_measurement(result->total_time));
}

/* call-seq:
   self_time -> float

Returns the total amount of time spent in this method. */
static VALUE
call_info_self_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return rb_float_new(convert_measurement(result->self_time));
}

/* call-seq:
   wait_time -> float

Returns the total amount of time this method waited for other threads. */
static VALUE
call_info_wait_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);

    return rb_float_new(convert_measurement(result->wait_time));
}

/* call-seq:
   children_time -> float

Returns the total amount of time spent in this method's children. */
static VALUE
call_info_children_time(VALUE self)
{
    prof_call_info_t *result = get_call_info_result(self);
    prof_measure_t children_time = result->total_time - result->self_time - result->wait_time;
    return rb_float_new(convert_measurement(children_time));
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
prof_method_create(st_data_t key, VALUE klass, ID mid, int depth, 
                   const char* source_file, int line)
{
    prof_method_t *result = ALLOC(prof_method_t);
    
    result->klass = klass;
    result->mid = mid;
    result->key = key;
    result->depth = depth;

    result->called = 0;
    result->total_time = 0;
    result->self_time = 0;
    result->wait_time = 0;
    result->parents = caller_table_create();
    result->children = caller_table_create();
    result->active_frame = 0;
    result->base = result;
        
    result->source_file = source_file;
    result->line = line;
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
    st_foreach(data->parents, free_call_infos, 0);
    caller_table_free(data->parents); 
    
    st_foreach(data->children, free_call_infos, 0);
    caller_table_free(data->children); 
    
    xfree(data);
}

static VALUE
prof_method_new(prof_method_t *result)
{
    return Data_Wrap_Struct(cMethodInfo, prof_method_mark, prof_method_free, result);
}

static prof_method_t *
get_prof_method(VALUE obj)
{
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

    return rb_float_new(convert_measurement(result->total_time));
}

/* call-seq:
   self_time -> float

Returns the total amount of time spent in this method. */
static VALUE
prof_method_self_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return rb_float_new(convert_measurement(result->self_time));
}

/* call-seq:
   wait_time -> float

Returns the total amount of time this method waited for other threads. */
static VALUE
prof_method_wait_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);

    return rb_float_new(convert_measurement(result->wait_time));
}

/* call-seq:
   line_no -> int

   returns the line number of the method */
static VALUE
prof_method_line(VALUE self)
{
    return rb_int_new(get_prof_method(self)->line);
}

/* call-seq:
   children_time -> float

Returns the total amount of time spent in this method's children. */
static VALUE
prof_method_children_time(VALUE self)
{
    prof_method_t *result = get_prof_method(self);
    prof_measure_t children_time = result->total_time - result->self_time - result->wait_time;
    return rb_float_new(convert_measurement(children_time));
}

/* call-seq:
   source_file => string

return the source file of the method 
*/
static VALUE prof_method_source_file(VALUE self)
{
    const char* sf = get_prof_method(self)->source_file;
    if(!sf)
    {
      return rb_str_new2("ruby_runtime");
    }
    else
    {
      return rb_str_new2(sf);
    }
}


/* call-seq:
   method_class -> klass

Returns the Ruby klass that owns this method. */
static VALUE
prof_method_klass(VALUE self)
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
   klass_name -> string

Returns the name of this method's class.  Singleton classes
will have the form <Object::Object>. */

static VALUE
prof_klass_name(VALUE self)
{
    prof_method_t *method = get_prof_method(self);
    return klass_name(method->klass);
}

/* call-seq:
   method_name -> string

Returns the name of this method in the format Object#method.  Singletons
methods will be returned in the format <Object::Object>#method.*/

static VALUE
prof_method_name(VALUE self)
{
    prof_method_t *method = get_prof_method(self);
    return method_name(method->mid, method->depth);
}

/* call-seq:
   full_name -> string

Returns the full name of this method in the format Object#method.*/

static VALUE
prof_full_name(VALUE self)
{
    prof_method_t *method = get_prof_method(self);
    return full_name(method->klass, method->mid, method->depth);
}

/* call-seq:
   called -> MethodInfo

For recursively called methods, returns the base method.  Otherwise, 
returns self. */
static VALUE
prof_method_base(VALUE self)
{
    prof_method_t *method = get_prof_method(self);
    
    if (method == method->base)
      return self;
    else
      /* Target is a pointer to a method_info - so we have to be careful
         about the GC.  We will wrap the method_info but provide no
         free method so the underlying object is not freed twice! */
      return Data_Wrap_Struct(cMethodInfo, NULL, NULL, method->base);
}

static int
prof_method_collect_call_infos(st_data_t key, st_data_t value, st_data_t result)
{
    /* Create a new Ruby CallInfo object and store it into the hash
       keyed on the parent's name.  We use the parent's name because
       we want to see that printed out for child records in
       a call graph. */
    prof_call_info_t *call_info = (prof_call_info_t *) value;
    VALUE arr = (VALUE) result;
    rb_ary_push(arr, call_info_new(call_info));
    return ST_CONTINUE;
}

/* call-seq:
   children -> hash

Returns an array of call info objects of methods that this method 
was called by (ie, parents).*/
static VALUE
prof_method_parents(VALUE self)
{
    /* Returns an array of call info objects for this
       method's callers (the methods this method called). */

    VALUE children = rb_ary_new();
    prof_method_t *result = get_prof_method(self);
    st_foreach(result->parents, prof_method_collect_call_infos, children);
    return children;
}


/* call-seq:
   children -> hash

Returns an array of call info objects of methods that this method 
called (ie, children).*/
static VALUE
prof_method_children(VALUE self)
{
    /* Returns an array of call info objects for this
       method's callees (the methods this method called). */

    VALUE children = rb_ary_new();
    prof_method_t *result = get_prof_method(self);
    st_foreach(result->children, prof_method_collect_call_infos, children);
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

    if (x->called == 0 && y->called == 0)
      return INT2FIX(0);
    else if (x->called == 0)
      return INT2FIX(1);
    else if (y->called == 0)
      return INT2FIX(-1);
    else if (x->total_time > y->total_time)
      return INT2FIX(-1);
    else if (x->total_time < y->total_time)
      return INT2FIX(1);
    else if (x->total_time == y->total_time)
      return INT2FIX(0);
    else
      return INT2FIX(0);
}

static int
collect_methods(st_data_t key, st_data_t value, st_data_t result)
{
    /* Called for each method stored in a thread's method table. 
       We want to store the method info information into an array.*/
    VALUE methods = (VALUE) result;
    prof_method_t *method = (prof_method_t *) value;
    rb_ary_push(methods, prof_method_new(method));

    return ST_CONTINUE;
}


/* ================  Thread Handling   =================*/

/* ---- Keeps track of thread's stack and methods ---- */
static thread_data_t*
thread_data_create()
{
    thread_data_t* result = ALLOC(thread_data_t);
    result->stack = stack_create();
    result->method_info_table = method_info_table_create();
    result->last_switch = 0;
    return result;
}

static void
thread_data_free(thread_data_t* thread_data)
{
    stack_free(thread_data->stack);
    method_info_table_free(thread_data->method_info_table);
    xfree(thread_data);
}


/* ---- Hash, keyed on thread, that stores thread's stack
        and methods---- */

static st_table *
threads_table_create()
{
    return st_init_numtable();
}

static inline size_t
threads_table_insert(st_table *table, VALUE thread, thread_data_t *thread_data)
{
    /* Its too slow to key on the real thread id so just typecast thread instead. */
    return st_insert(table, (st_data_t ) thread, (st_data_t) thread_data);
}

static inline thread_data_t *
threads_table_lookup(st_table *table, long thread_id)
{
    thread_data_t* result;
    st_data_t val;

    /* Its too slow to key on the real thread id so just typecast thread instead. */
    if (st_lookup(table, (st_data_t) thread_id, &val))
    {
      result = (thread_data_t *) val;
    }
    else
    {
        result = thread_data_create();
        result->thread_id = thread_id;

        /* Insert the table */
        threads_table_insert(threads_tbl, thread_id, result);
    }
    return result;
}

static int
free_thread_data(st_data_t key, st_data_t value, st_data_t dummy)
{
    thread_data_free((thread_data_t*)value);
    return ST_CONTINUE;
}


static void
threads_table_free(st_table *table)
{
    st_foreach(table, free_thread_data, 0);
    st_free_table(table);
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
    
    VALUE methods = rb_ary_new();
    
    /* Now collect an array of all the called methods */
    st_foreach(thread_data->method_info_table, collect_methods, methods);
    
    /* Store the results in the threads hash keyed on the thread id. */
    rb_hash_aset(threads_hash, ULONG2NUM(thread_data->thread_id), methods);

    return ST_CONTINUE;
}


/* ================  Profiling    =================*/
/* Copied from eval.c */
static char *
get_event_name(rb_event_flag_t event)
{
  switch (event) {
    case RUBY_EVENT_LINE:
  return "line";
    case RUBY_EVENT_CLASS:
  return "class";
    case RUBY_EVENT_END:
  return "end";
    case RUBY_EVENT_CALL:
  return "call";
    case RUBY_EVENT_RETURN:
  return "return";
    case RUBY_EVENT_C_CALL:
  return "c-call";
    case RUBY_EVENT_C_RETURN:
  return "c-return";
    case RUBY_EVENT_RAISE:
  return "raise";
    default:
  return "unknown";
    }
}

static void
update_result(thread_data_t* thread_data,
              prof_measure_t total_time,
              prof_frame_t  *parent_frame, prof_frame_t *child_frame)
{
    prof_method_t *parent = NULL;
    prof_method_t *child = child_frame->method;
    prof_call_info_t *parent_call_info = NULL;
    prof_call_info_t *child_call_info = NULL;
    
    prof_measure_t wait_time = child_frame->wait_time;
    prof_measure_t self_time = total_time - child_frame->child_time - wait_time;

    /* Update information about the child (ie, the current method) */
    child->called++;
    child->total_time += total_time;
    child->self_time += self_time;
    child->wait_time += wait_time;

    if (!parent_frame) return;
    
    parent = parent_frame->method;
        
    child_call_info = caller_table_lookup(parent->children, child->key);
    if (child_call_info == NULL)
    {
        child_call_info = call_info_create(child);
        caller_table_insert(parent->children, child->key, child_call_info);
    }

    child_call_info->called++;
    child_call_info->total_time += total_time;
    child_call_info->self_time += self_time;
    child_call_info->wait_time += wait_time;
    child_call_info->line = parent_frame->line;
        
    /* Update child's parent information  */
    parent_call_info = caller_table_lookup(child->parents, parent->key);
    if (parent_call_info == NULL)
    {
        parent_call_info = call_info_create(parent);
        caller_table_insert(child->parents, parent->key, parent_call_info);
    }
    
    parent_call_info->called++;
    parent_call_info->total_time += total_time;
    parent_call_info->self_time += self_time;
    parent_call_info->wait_time += wait_time;
    parent_call_info->line = (parent_frame ? parent_frame->line : 0);
    
    
    /* If the caller is the top of the stack, the merge in
       all the child results.  We have to do this because
       the top method is never popped since sooner or later
       the user has to call RubyProf::stop.*/
      
    if (stack_size(thread_data->stack) == 1)
    {
      parent->total_time += total_time;
      parent->wait_time += wait_time;
    }
}


#ifdef RUBY_VM
static void
prof_event_hook(rb_event_flag_t event, VALUE data, VALUE self, ID mid, VALUE klass)
#else
static void
prof_event_hook(rb_event_flag_t event, NODE *node, VALUE self, ID mid, VALUE klass)
#endif
{
    
    VALUE thread;
    prof_measure_t now = 0;
    thread_data_t* thread_data = NULL;
    long thread_id = 0;
    prof_frame_t *frame = NULL;
#ifdef RUBY_VM

    if (event != RUBY_EVENT_C_CALL &&
  event != RUBY_EVENT_C_RETURN) {
  VALUE thread = rb_thread_current();
  rb_frame_method_id_and_class(&mid, &klass);
    }
#endif
    /*  This code is here for debug purposes - uncomment it out
        when debugging to see a print out of exactly what the
        profiler is tracing. 
    {
        st_data_t key = 0;
        static unsigned long last_thread_id = 0;

        VALUE thread = rb_thread_current();
        unsigned long thread_id = get_thread_id(thread);
        char* class_name = rb_obj_classname(klass);
        char* method_name = rb_id2name(mid);
        char* source_file = node ? node->nd_file : 0;
        unsigned int source_line = node ? nd_line(node) : 0;
        char* event_name = get_event_name(event);
        
        if (last_thread_id != thread_id)
          printf("\n");
          
        if (klass != 0)
          klass = (BUILTIN_TYPE(klass) == T_ICLASS ? RBASIC(klass)->klass : klass);
        key = method_key(klass, mid, 0);          
        printf("%2u: %-8s :%2d  %s#%s (%u)\n",
               thread_id, event_name, source_line, class_name, method_name, key);
        last_thread_id = thread_id;               
    } */
    
    /* Special case - skip any methods from the mProf 
       module, such as Prof.stop, since they clutter
       the results but aren't important to them results. */
    if (self == mProf) return;

    /* Get current measurement*/
    now = get_measurement();
    
    /* Get the current thread information. */
    thread = rb_thread_current();
    thread_id = get_thread_id(thread);
    
    /* Was there a context switch? */
    if (!last_thread_data || last_thread_data->thread_id != thread_id)
    {
      prof_measure_t wait_time = 0;
      
      /* Get new thread information. */
      thread_data = threads_table_lookup(threads_tbl, thread_id);

      /* How long has this thread been waiting? */
      wait_time = now - thread_data->last_switch;
      thread_data->last_switch = 0;

      /* Get the frame at the top of the stack.  This may represent
         the current method (EVENT_LINE, EVENT_RETURN)  or the
         previous method (EVENT_CALL).*/
      frame = stack_peek(thread_data->stack);
    
      if (frame)
        frame->wait_time += wait_time;
        
      /* Save on the last thread the time of the context switch
         and reset this thread's last context switch to 0.*/
      if (last_thread_data)
        last_thread_data->last_switch = now;
        
      last_thread_data = thread_data;
    }
    else
    {
      thread_data = last_thread_data;
      frame = stack_peek(thread_data->stack);
    }
    
    switch (event) {
    case RUBY_EVENT_LINE:
    {
      /* Keep track of the current line number in this method.  When
         a new method is called, we know what line number it was 
         called from. */
      if (frame)
      {
#ifdef RUBY_VM
    frame->line = rb_sourceline();
#else
        if (node)
          frame->line = nd_line(node);
#endif
        break;
      }
      /* If we get here there was no frame, which means this is 
         the first method seen for this thread, so fall through
         to below to create it. */
    }
    case RUBY_EVENT_CALL:
    case RUBY_EVENT_C_CALL:
    {
        int depth = 0;
        st_data_t key = 0;
        prof_method_t *method = NULL;

        /* Is this an include for a module?  If so get the actual
           module class since we want to combine all profiling
           results for that module. */
        
        if (klass != 0)
          klass = (BUILTIN_TYPE(klass) == T_ICLASS ? RBASIC(klass)->klass : klass);
          
        key = method_key(klass, mid, 0);
   
        method = method_info_table_lookup(thread_data->method_info_table, key);
        
        if (!method)
        {
          const char* source_file = rb_sourcefile();
          int line = rb_sourceline();
          
          /* Line numbers are not accurate for c method calls */
            if (event == RUBY_EVENT_C_CALL)
            {
              line = 0;
              source_file = NULL;
            }
            
          method = prof_method_create(key, klass, mid, depth, source_file, line);
          method_info_table_insert(thread_data->method_info_table, key, method);
        }
        
        depth = method->active_frame;
        method->active_frame++;                  
        
        if (depth > 0)
        {
          prof_method_t *base_method = method;
          key = method_key(klass, mid, depth);
          method = method_info_table_lookup(thread_data->method_info_table, key);
          
          if (!method)
          {
            const char* source_file = rb_sourcefile();
            int line = rb_sourceline();
            
            /* Line numbers are not accurate for c method calls */
            if (event == RUBY_EVENT_C_CALL)
            {
              line = 0;
              source_file = NULL;
            }
              
            method = prof_method_create(key, klass, mid, depth, source_file, line);
            method->base = base_method;
            method_info_table_insert(thread_data->method_info_table, key, method);
          }
        }

        /* Push a new frame onto the stack */
        frame = stack_push(thread_data->stack);
        frame->method = method;
        frame->start_time = now;
        frame->wait_time = 0;
        frame->child_time = 0;
        frame->line = rb_sourceline();

        break;
    }
    case RUBY_EVENT_RETURN:
    case RUBY_EVENT_C_RETURN:
    {
        prof_frame_t* caller_frame = NULL;

        prof_measure_t total_time;

        frame = stack_pop(thread_data->stack);
        caller_frame = stack_peek(thread_data->stack);
          
        /* Frame can be null.  This can happen if RubProf.start is called from
           a method that exits.  And it can happen if an exception is raised
           in code that is being profiled and the stack unwinds (RubProf is
           not notified of that by the ruby runtime. */
        if (frame == NULL) return;

        total_time = now - frame->start_time;

        if (caller_frame)
        {
            caller_frame->child_time += total_time;
        }
          
        frame->method->base->active_frame--;
        
        update_result(thread_data, total_time, caller_frame, frame);
        break;
      }
    }
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
    if (BUILTIN_TYPE(obj) != T_DATA ||
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
   measure_mode -> measure_mode
   
   Returns what ruby-prof is measuring.  Valid values include:
   
   *RubyProf::PROCESS_TIME - Measure process time.  This is default.  It is implemented using the clock functions in the C Runtime library.
   *RubyProf::WALL_TIME - Measure wall time using gettimeofday on Linx and GetLocalTime on Windows
   *RubyProf::CPU_TIME - Measure time using the CPU clock counter.  This mode is only supported on Pentium or PowerPC platforms. 
   *RubyProf::ALLOCATIONS - Measure object allocations.  This requires a patched Ruby interpreter.*/
static VALUE
prof_get_measure_mode(VALUE self)
{
    return INT2NUM(measure_mode);
}

/* call-seq:
   measure_mode=value -> void
   
   Specifies what ruby-prof should measure.  Valid values include:
   
   *RubyProf::PROCESS_TIME - Measure process time.  This is default.  It is implemented using the clock functions in the C Runtime library.
   *RubyProf::WALL_TIME - Measure wall time using gettimeofday on Linx and GetLocalTime on Windows
   *RubyProf::CPU_TIME - Measure time using the CPU clock counter.  This mode is only supported on Pentium or PowerPC platforms. 
   *RubyProf::ALLOCATIONS - Measure object allocations.  This requires a patched Ruby interpreter.*/
static VALUE
prof_set_measure_mode(VALUE self, VALUE val)
{
    long mode = NUM2LONG(val);

    if (threads_tbl)
    {
      rb_raise(rb_eRuntimeError, "can't set measure_mode while profiling");
    }

    switch (mode) {
      case MEASURE_PROCESS_TIME:
        get_measurement = measure_process_time;
        convert_measurement = convert_process_time;
        break;
        
      case MEASURE_WALL_TIME:
        get_measurement = measure_wall_time;
        convert_measurement = convert_wall_time;
        break;
        
      #if defined(MEASURE_CPU_TIME)
      case MEASURE_CPU_TIME:
        if (cpu_frequency == 0)
            cpu_frequency = measure_cpu_time();
        get_measurement = measure_cpu_time;
        convert_measurement = convert_cpu_time;
        break;
      #endif
              
      #if defined(MEASURE_ALLOCATIONS)
      case MEASURE_ALLOCATIONS:
        get_measurement = measure_allocations;
        convert_measurement = convert_allocations;
        break;
      #endif
        
      default:
        rb_raise(rb_eArgError, "invalid mode: %d", mode);
        break;
    }
    
    measure_mode = mode;
    return val;
}

/* =========  Profiling ============= */


/* call-seq:
   running? -> boolean
   
   Returns whether a profile is currently running.*/
static VALUE
prof_running(VALUE self)
{
    if (threads_tbl != NULL)
        return Qtrue;
    else
        return Qfalse;
}

/* call-seq:
   start -> void
   
   Starts recording profile data.*/
static VALUE
prof_start(VALUE self)
{
    if (threads_tbl != NULL)
    {
        rb_raise(rb_eRuntimeError, "RubyProf.start was already called");
    }

    /* Setup globals */
    last_thread_data = NULL;
    threads_tbl = threads_table_create();
    
#ifdef RUBY_VM
    rb_add_event_hook(prof_event_hook,
          RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
          RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN 
          | RUBY_EVENT_LINE, Qnil);
#else
    rb_add_event_hook(prof_event_hook,
          RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
          RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN 
          | RUBY_EVENT_LINE);
#endif

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
        rb_raise(rb_eRuntimeError, "RubyProf is not running.");
    }

    /* Now unregister from event   */
    rb_remove_event_hook(prof_event_hook);

    /* Create the result */
    result = prof_result_new();

    /* Unset the last_thread_data (very important!) 
       and the threads table */
    last_thread_data = NULL;
    threads_table_free(threads_tbl);
    threads_tbl = NULL;

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
    rb_define_module_function(mProf, "running?", prof_running, 0);
    rb_define_module_function(mProf, "profile", prof_profile, 0);
    
    rb_define_singleton_method(mProf, "measure_mode", prof_get_measure_mode, 0);
    rb_define_singleton_method(mProf, "measure_mode=", prof_set_measure_mode, 1);

    rb_define_const(mProf, "CLOCKS_PER_SEC", INT2NUM(CLOCKS_PER_SEC));
    rb_define_const(mProf, "PROCESS_TIME", INT2NUM(MEASURE_PROCESS_TIME));
    rb_define_const(mProf, "WALL_TIME", INT2NUM(MEASURE_WALL_TIME));

    #ifndef MEASURE_CPU_TIME
    rb_define_const(mProf, "CPU_TIME", Qnil);
    #else
    rb_define_const(mProf, "CPU_TIME", INT2NUM(MEASURE_CPU_TIME));
    rb_define_singleton_method(mProf, "cpu_frequency", prof_get_cpu_frequency, 0); /* in measure_cpu_time.h */
    rb_define_singleton_method(mProf, "cpu_frequency=", prof_set_cpu_frequency, 1); /* in measure_cpu_time.h */
    #endif
        
    #ifndef MEASURE_ALLOCATIONS
    rb_define_const(mProf, "ALLOCATIONS", Qnil);
    #else
    rb_define_const(mProf, "ALLOCATIONS", INT2NUM(MEASURE_ALLOCATIONS));
    #endif
    
    cResult = rb_define_class_under(mProf, "Result", rb_cObject);
    rb_undef_method(CLASS_OF(cMethodInfo), "new");
    rb_define_method(cResult, "threads", prof_result_threads, 0);

    cMethodInfo = rb_define_class_under(mProf, "MethodInfo", rb_cObject);
    rb_include_module(cMethodInfo, rb_mComparable);
    rb_undef_method(CLASS_OF(cMethodInfo), "new");
    
    rb_define_method(cMethodInfo, "klass", prof_method_klass, 0);
    rb_define_method(cMethodInfo, "klass_name", prof_klass_name, 0);
    rb_define_method(cMethodInfo, "method_name", prof_method_name, 0);
    rb_define_method(cMethodInfo, "full_name", prof_full_name, 0);
    rb_define_method(cMethodInfo, "method_id", prof_method_id, 0);
    rb_define_method(cMethodInfo, "base", prof_method_base, 0);
    
    rb_define_method(cMethodInfo, "parents", prof_method_parents, 0);
    rb_define_method(cMethodInfo, "children", prof_method_children, 0);
    rb_define_method(cMethodInfo, "<=>", prof_method_cmp, 1);
    rb_define_method(cMethodInfo, "source_file", prof_method_source_file,0);
    rb_define_method(cMethodInfo, "line", prof_method_line, 0);
    rb_define_method(cMethodInfo, "called", prof_method_called, 0);
    rb_define_method(cMethodInfo, "total_time", prof_method_total_time, 0);
    rb_define_method(cMethodInfo, "self_time", prof_method_self_time, 0);
    rb_define_method(cMethodInfo, "wait_time", prof_method_wait_time, 0);
    rb_define_method(cMethodInfo, "children_time", prof_method_children_time, 0);

    cCallInfo = rb_define_class_under(mProf, "CallInfo", rb_cObject);
    rb_undef_method(CLASS_OF(cCallInfo), "new");
    rb_define_method(cCallInfo, "target", call_info_target, 0);
    rb_define_method(cCallInfo, "called", call_info_called, 0);
    rb_define_method(cCallInfo, "total_time", call_info_total_time, 0);
    rb_define_method(cCallInfo, "self_time", call_info_self_time, 0);
    rb_define_method(cCallInfo, "wait_time", call_info_wait_time, 0);
    rb_define_method(cCallInfo, "line", call_info_line, 0);
    rb_define_method(cCallInfo, "children_time", call_info_children_time, 0);
}

