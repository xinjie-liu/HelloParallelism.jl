# HelloParallelism.jl

Example designs for parallel computation.

- green threading (coroutines/tasks on a single thread/worker)
- shared-memory multi-threading (fork-join on a single worker)
- distributed memory multi-threading (multiple workers that can be spread across multiple nodes)
- multi-level parallelism (multiple (distributed) works using shared-memory parallelism)
