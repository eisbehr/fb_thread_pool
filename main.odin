package main

import "core:fmt"
import "core:runtime"
import "core:time"
import "core:intrinsics"
import "core:math/rand"
import pool "fb_thread_pool"

task_proc_simple :: proc(task: ^pool.Task) {
	r := rand.create(u64(task.user_index))
	ms:= time.Duration(50+rand.int31_max(450, &r))
	time.sleep(ms*time.Millisecond)
}

task_proc_spawning :: proc(task: ^pool.Task) {
	tp := cast(^pool.Pool)task.data
	if(task.user_index<=5) {
		pool.add(tp, task_proc_spawning, task.data, task.user_index+1)
		pool.add(tp, task_proc_spawning, task.data, task.user_index+1)
	}
	r := rand.create(u64(task.user_index))
	ms:= time.Duration(50+rand.int31_max(450, &r))
	time.sleep(ms*time.Millisecond)
}

tests :: proc() {
	fmt.println("Beginning thread pool")
	tp: pool.Pool
	NUM_TASKS :: 25
	num_tasks:= NUM_TASKS
	r := rand.create(u64(intrinsics.read_cycle_counter()))
	num_threads:= int(rand.int31_max(15, &r))
	fmt.printf("Running pool with %i threads\n", num_threads)

	// explicitly use default allocator, which should be thread safe
	pool.init(&tp, num_threads, runtime.default_allocator())

	for i in 1..num_tasks {
		pool.add(&tp, task_proc_simple, nil, int(rand.int31(&r)))
	}
	fmt.println("Waiting tasks: ", pool.num_waiting(&tp))
	pool.start(&tp)

	num_tasks_done:int
	num_random_tasks:int
	MAX_RANDOM_ADD :: 10
	for !pool.is_empty(&tp) {
		if pool.num_done(&tp)>0 {
			for t in pool.pop_done(&tp) {
				num_tasks_done += 1

				if rand.int31_max(10) == 0 {
					fmt.println("randomly adding another task")
					num_tasks += 1
					num_random_tasks += 1
					pool.add(&tp, task_proc_simple, nil, int(rand.int31(&r)))
				}
			}
		}
		time.sleep(100*time.Millisecond)
	}
	fmt.printf("Tasks done %i/%i (%i+%i)\n", num_tasks_done, num_tasks, NUM_TASKS, num_random_tasks)
	assert(num_tasks_done==num_tasks)

	fmt.println("Testing tasks that spawn more tasks")
	NUM_SPAWNING_TASKS :: 1+2+4+8+16+32
	num_tasks += NUM_SPAWNING_TASKS
	pool.add(&tp, task_proc_spawning, &tp, 1)
	for !pool.is_empty(&tp) {
		if pool.num_done(&tp)>0 {
			for t in pool.pop_done(&tp) {
				fmt.printf("Done task number %i\n", t.user_index)
				num_tasks_done += 1
				}
		}
		time.sleep(100*time.Millisecond)
	}
	fmt.printf("Tasks done %i/%i (%i+%i+%i)\n", num_tasks_done, num_tasks, NUM_TASKS, num_random_tasks, NUM_SPAWNING_TASKS)
	assert(num_tasks_done==num_tasks)

	fmt.println("Add another batch of tasks")
	for i in 1..NUM_TASKS {
		num_tasks += 1
		pool.add(&tp, task_proc_simple, nil, int(rand.int31(&r)))
	}

	fmt.println("waiting for all tasks to process, and doing work on this thread too")
	pool.finish(&tp)
	if pool.num_outstanding(&tp)>0 {
		fmt.println("Error, still outstanding tasks left after pool_finish(&tp)")
		return
	}

	for _ in pool.pop_done(&tp) {
		//fmt.printf("Done task number %i -> %i\n", t.user_index-10, t.user_index)
		num_tasks_done += 1
	}
	fmt.printf("Tasks done %i/%i (%i+%i+%i+%i)\n", num_tasks_done, num_tasks, NUM_TASKS, num_random_tasks, NUM_SPAWNING_TASKS, NUM_TASKS)
	assert(num_tasks_done==num_tasks)
	pool.destroy(&tp)
	fmt.println("Thread pool done")
}

main :: proc() {
	NUM_ITERATIONS :: 1000
	fmt.printf("Running a batch of %i iterations\n", NUM_ITERATIONS)
	for i in 1..NUM_ITERATIONS {
		fmt.printf("BATCH ITERATION %i/%i\n", i, NUM_ITERATIONS)
		tests()
	}
	fmt.printf("All %i iterations successful\n", NUM_ITERATIONS)
}
