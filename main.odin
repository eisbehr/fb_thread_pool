package main

import "core:fmt"
import "core:time"
import "core:math/rand"
import th "fb_thread_pool"

task_proc :: proc(task: ^th.Task) {
	task.user_index += 10
	time.sleep(1*time.Second)
}

main :: proc() {
	fmt.println("Beginning thread pool")
	pool: th.Pool
	NUM_TASKS :: 25
	num_tasks:= NUM_TASKS
	th.pool_init(&pool, 10)

	for i in 1..num_tasks {
		th.pool_add_task(&pool, task_proc, nil, i)
	}
	fmt.println("Waiting tasks: ", th.pool_num_waiting_tasks(&pool))
	th.pool_start(&pool)

	num_tasks_done:= 0
	MAX_RANDOM_ADD :: 10
	for th.pool_num_outstanding_tasks(&pool)>0 {
		for t in th.pool_pop_done_task(&pool) {
			fmt.printf("Done task number %i -> %i\n", t.user_index-10, t.user_index)
			num_tasks_done += 1

			if rand.int_max(10) == 0 {
				fmt.println("randomly adding another task")
				num_tasks += 1
				th.pool_add_task(&pool, task_proc, nil, num_tasks)
			}
		}
	}
	fmt.printf("Tasks done %i/%i inital batch %i\n", num_tasks_done, num_tasks, NUM_TASKS)
	fmt.println("Add another batch of tasks")
	for i in 1..NUM_TASKS {
		num_tasks += 1
		th.pool_add_task(&pool, task_proc, nil, num_tasks)
	}

	fmt.println("waiting for all tasks to process, and doing work on this thread too")
	th.pool_finish(&pool)
	if th.pool_num_outstanding_tasks(&pool)>0 {
		fmt.println("Error, still outstanding tasks left after pool_wait_and_process(&pool)")
		return
	}
	for t in th.pool_pop_done_task(&pool) {
		fmt.printf("Done task number %i -> %i\n", t.user_index-10, t.user_index)
		num_tasks_done += 1
	}
	fmt.printf("More Tasks done %i/%i inital batch %i, second batch as well\n", num_tasks_done, num_tasks, NUM_TASKS)

	fmt.println("Thread pool done")
}
