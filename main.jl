# Note: This script contains asynchronous green threading routines (tasks on a
# single thread) as well as shared-memory paralellisim (traditional
# multi-threading).
#
# TODO: Distributed

import Distributed

const N_runs = 1000
const buffer_size = 10
const consumer_sleep_time = 0.01

#====================== dumme work that we want to get done =======================#

Distributed.@everywhere include("worker_code.jl")

function consume(channel)
    println("Waiting for results.")
    for result in channel
        println(result)
        sleep(consumer_sleep_time)
    end
end

#=============== Tasks/Coroutines: (green) threads on a single core ===============#
"""
Green Threading: green threading with a task bound to channel for automatic
channel management.

The manager task bound to `result_channel` is used to keep channel alive until the
for loop is `@sync`ed again at the end.

If `spawn` is set to `true`, the manager task is launched in a separate thread.
This is a good idea if `some_work_that_takes_time` requires some heavy lifting (not
just `sleep`ing) since otherwise the main thread may be to busy to ever consume the
results.
"""
function run_green_threaded(; spawn=false)
    # create a task from the anonymous function bound to a Channel such that the
    # channel is automatically closed when the Task finishes
    result_channel = Channel(buffer_size; spawn) do ch
        @sync for id in 1:N_runs
            @async put!(ch, some_work_that_takes_time(id))
        end
        println("joined again")
    end

    consume(result_channel)
end

#=================== Multithreading with shared-memory threads ====================#

"""
Multithreading 1: same as above buth with `Threads.@threads` annotation on the
Channel task.

Warning: this does *not* reliably work if `spawn` is set to true since
`Threads.@threads` can only spawn new threads from `threadid()==1`
"""
function run_multithreaded()
    # create a manager task from the anonymous function bound to a Channel such that the
    # channel is automatically closed when the manager task finishes
    # all this task does is spawn a bunch of tasks on different threads and wait for
    # them do finish before closing the channel.
    result_channel = Channel(buffer_size) do ch
        # Note: nice thing here: Threads.@threads makes sure that the threads are
        # joined before exiting the anonymous function and hence keeps the channel
        # alive until we are done.. This would not be the case if we were using
        # `@async`; (there we would need to @sync manually)
        Threads.@threads for id in 1:N_runs
            put!(ch, some_work_that_takes_time(id))
        end
        println("joined again")
    end

    # the for-loop automatically takes from `result_channel` until the task bound
    # the channel above finished. So no need to count here.
    consume(result_channel)
end

#=== Distributed accross *processe*, potentially live on another machine (node)====#

"Launch workers locally and remotely. Note that you may have to load the code on the
launched workers explicity with `Distributed.@everywhere ...`."
function launch_workers(;n_remote=:auto, n_local=10)
    if n_remote == :auto || n_remote > 0
        # rechenknecht node only works in HULKs network (VPN)
        Distributed.addprocs([("10.2.24.6", n_remote)])
    end
    if use_local
        Distributed.addprocs(n_local)
    end
end

"Stop all workers."
function stop_workers()
    Distributed.rmprocs(Distributed.workers())
end

"""
The multi-process version of paralellisim for distribution accross multiple
machines.

Note: In order for this to work, you need to launch workers with
`Distributed.addprocs(cluster_manager)`.
"""
function run_distributed()
    # This is a bit of an ugly way to do it since I'd rather prefer to use a
    # `Distributed.RemoteChannel`. However, I can't find a way to hand a
    # `RemoteChannel` to a worker, other than using a rather ugly `remote_do`
    # construct. With `Distributed.@distributed` or `Distributed.@spawnat` the
    # channel seems to be copied, not referenced (?)
    # TODO: ask an discourse
    #
    # Create a manager task that asynchronously spawns tasks on workers and `put!`s
    # the results in the managed channel. This way, we can reuse the entire
    # `consume` logic from above (which does not seem to be possible if we used a
    # `RemoteChannel` since a `RemoteChannel` is not iterable (and does not know if
    # it's empty)
    result_channel = Channel(buffer_size) do ch
        @sync for id in 1:N_runs
            @async put!(ch, Distributed.@fetch some_work_that_takes_time(id))
        end
        println("Joined again.")
    end

    consume(result_channel)
end
