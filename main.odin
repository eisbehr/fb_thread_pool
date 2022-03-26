package main

import "core:fmt"
import "core:time"
import "core:math/rand"
import pool "fb_thread_pool"

task_proc :: proc(task: ^pool.Task) {
	task.user_index += 10
	time.sleep(1*time.Second)
}

main :: proc() {
	fmt.println("Beginning thread pool")
	tp: pool.Pool
	NUM_TASKS :: 25
	num_tasks:= NUM_TASKS
	pool.init(&tp, 10)

	for i in 1..num_tasks {
		pool.add_task(&tp, task_proc, nil, i)
	}
	fmt.println("Waiting tasks: ", pool.num_waiting_tasks(&tp))
	pool.start(&tp)

	num_tasks_done:= 0
	MAX_RANDOM_ADD :: 10
	for pool.num_outstanding_tasks(&tp)>0 {
		for t in pool.pop_done_task(&tp) {
			fmt.printf("Done task number %i -> %i\n", t.user_index-10, t.user_index)
			num_tasks_done += 1

			if rand.int_max(10) == 0 {
				fmt.println("randomly adding another task")
				num_tasks += 1
				pool.add_task(&tp, task_proc, nil, num_tasks)
			}
		}
	}
	fmt.printf("Tasks done %i/%i inital batch %i\n", num_tasks_done, num_tasks, NUM_TASKS)
	fmt.println("Add another batch of tasks")
	for i in 1..NUM_TASKS {
		num_tasks += 1
		pool.add_task(&tp, task_proc, nil, num_tasks)
	}

	fmt.println("waiting for all tasks to process, and doing work on this thread too")
	pool.finish(&tp)
	if pool.num_outstanding_tasks(&tp)>0 {
		fmt.println("Error, still outstanding tasks left after pool_finish(&tp)")
		return
	}
	for t in pool.pop_done_task(&tp) {
		fmt.printf("Done task number %i -> %i\n", t.user_index-10, t.user_index)
		num_tasks_done += 1
	}
	fmt.printf("More Tasks done %i/%i inital batch %i, second batch as well\n", num_tasks_done, num_tasks, NUM_TASKS)
	pool.destroy(&tp)
	fmt.println("Thread pool done")
}
