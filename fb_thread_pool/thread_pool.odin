package fb_thread_pool

import "core:intrinsics"
import "core:sync"
import "core:mem"
import th "core:thread"

Task_Proc :: #type proc(task: ^Task)

Task :: struct {
	procedure: Task_Proc,
	data: rawptr,
	user_index: int,
}

Task_Id :: distinct i32

// NOTE: Do not access the pools members directly while the pool threads are
// running since they use different kinds of locking and mutual exclusion
// devices. Careless access can and will lead to nasty bugs
Pool :: struct {
	allocator:             mem.Allocator,
	mutex:                 sync.Mutex,
	sem_available:         sync.Semaphore,

	// the following values are atomic and can be read without taking the mutex
	num_waiting : int,
	num_in_processing: int,
	num_outstanding: int, // num_waiting + num_in_processing
	num_done: int,
	// end of atomics

	is_running:            bool,

	threads: []^th.Thread,

	tasks: [dynamic]Task,
	tasks_done: [dynamic]Task,
}

pool_init :: proc(pool: ^Pool, thread_count: int, allocator := context.allocator) {
	worker_thread_internal :: proc(t: ^th.Thread) {
		pool := (^Pool)(t.data)

		for pool.is_running {
			sync.semaphore_wait_for(&pool.sem_available)

			if task, ok := pool_pop_waiting_task(pool); ok {
				pool_do_work(pool, &task)
			}
		}

		sync.semaphore_post(&pool.sem_available, 1)
	}

	context.allocator = allocator
	pool.allocator = allocator
	pool.tasks = make([dynamic]Task)
	pool.tasks_done = make([dynamic]Task)
	pool.threads = make([]^th.Thread, thread_count)

	sync.mutex_init(&pool.mutex)
	sync.semaphore_init(&pool.sem_available)
	pool.is_running = true

	for _, i in pool.threads {
		t := th.create(worker_thread_internal)
		t.user_index = i
		t.data = pool
		pool.threads[i] = t
	}
}

pool_destroy :: proc(pool: ^Pool) {
	delete(pool.tasks)

	for thread in &pool.threads {
		th.destroy(thread)
	}

	delete(pool.threads, pool.allocator)

	sync.mutex_destroy(&pool.mutex)
	sync.semaphore_destroy(&pool.sem_available)
}

pool_start :: proc(pool: ^Pool) {
	for t in pool.threads {
		th.start(t)
	}
}

pool_join :: proc(pool: ^Pool) {
	pool.is_running = false

	sync.semaphore_post(&pool.sem_available, len(pool.threads))

	th.yield()

	for t in pool.threads {
		th.join(t)
	}
}

pool_add_task :: proc(pool: ^Pool, procedure: Task_Proc, data: rawptr, user_index: int = 0) {
	sync.mutex_lock(&pool.mutex)
	defer sync.mutex_unlock(&pool.mutex)

	task: Task
	task.procedure = procedure
	task.data = data
	task.user_index = user_index

	append(&pool.tasks, task)
	intrinsics.atomic_add(&pool.num_waiting, 1)
	intrinsics.atomic_add(&pool.num_outstanding, 1)
	sync.semaphore_post(&pool.sem_available, 1)
}

pool_num_waiting_tasks :: #force_inline proc(pool: ^Pool) -> int {
	return intrinsics.atomic_load(&pool.num_waiting)
}

pool_num_in_processing_tasks :: #force_inline proc(pool: ^Pool) -> int {
	return intrinsics.atomic_load(&pool.num_in_processing)
}

// Outstanding tasks are all tasks that are not done, that is, tasks that are
// waiting, as well as tasks that are currently being processed
pool_num_outstanding_tasks :: #force_inline proc(pool: ^Pool) -> int {
	return intrinsics.atomic_load(&pool.num_outstanding)
}

pool_num_done_tasks :: #force_inline proc(pool: ^Pool) -> int {
	return intrinsics.atomic_load(&pool.num_done)
}

pool_pop_waiting_task :: proc(pool: ^Pool) -> (task: Task, got_task: bool = false) {
	sync.mutex_lock(&pool.mutex)
	defer sync.mutex_unlock(&pool.mutex)

	if len(pool.tasks) != 0 {
		intrinsics.atomic_sub(&pool.num_waiting, 1)
		intrinsics.atomic_add(&pool.num_in_processing, 1)
		task = pop_front(&pool.tasks)
		got_task = true
	}

	return
}

pool_pop_done_task :: proc(pool: ^Pool) -> (task: Task, got_task: bool = false) {
	sync.mutex_lock(&pool.mutex)
	defer sync.mutex_unlock(&pool.mutex)

	if len(pool.tasks_done) != 0 {
		intrinsics.atomic_sub(&pool.num_done, 1)
		task = pop_front(&pool.tasks_done)
		got_task = true
	}

	return
}

pool_do_work :: proc(pool: ^Pool, task: ^Task) {
	task.procedure(task)

	sync.mutex_lock(&pool.mutex)
	defer sync.mutex_unlock(&pool.mutex)

	append(&pool.tasks_done, task^)
	intrinsics.atomic_sub(&pool.num_in_processing, 1)
	intrinsics.atomic_sub(&pool.num_outstanding, 1)
	intrinsics.atomic_add(&pool.num_done, 1)
}

// process the rest of the tasks, also use this thread for processing, then join
// all the pool threads.
pool_finish :: proc(pool: ^Pool) {
	for task in pool_pop_waiting_task(pool) {
		t:= task
		pool_do_work(pool, &t)
	}
	pool_join(pool)
}
