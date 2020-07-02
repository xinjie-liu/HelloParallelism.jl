import Distributed

const N_jobs = 100
const buffer_size = 100
const consumer_sleep_time = 0.0

#====================== dumme work that we want to get done =======================#

Distributed.@everywhere include("worker_code.jl")

function consume(channel)
    println("Waiting for results...")
    for result in channel
        println(result)
        sleep(consumer_sleep_time)
    end
end

function consume_unmanaged(channel, Ntake)
    println("Waiting for results...")
    for _ in 1:Ntake
        println(take!(channel))
        sleep(consumer_sleep_time)
    end
    close(channel)
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
        @sync for job_id in 1:N_jobs
            @async put!(ch, some_work_that_takes_time(job_id))
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
        Threads.@threads for job_id in 1:N_jobs
            put!(ch, some_work_that_takes_time(job_id))
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
function start_workers(;n_remote=:auto, n_local=10)
    usable(n) = n == :auto || n > 0

    if usable(n_remote)
        # rechenknecht node only works in HULKs network (VPN)
        Distributed.addprocs([("10.2.24.6", n_remote)])
    end
    if usable(n_local)
        Distributed.addprocs(n_local)
    end

    Distributed.workers()
end

"Stop all workers."
function stop_workers()
    Distributed.rmprocs(Distributed.workers())
end

"""
The multi-process version of paralellisim for distribution accross multiple
machines.

This version uses a manager task that fetches the results form the workers
and `put!`s them on the `result_channel`.

Note: In order for this to work, you need to launch workers with; e.g. with
`start_workers` above.
"""
function run_distributed_fetch(spawn=true)
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
    result_channel = Channel(buffer_size; spawn) do ch
        @sync for job_id in 1:N_jobs
            @async put!(ch, Distributed.@fetch some_work_that_takes_time(job_id))
        end
        println("joined again.")
    end

    consume(result_channel)
end

"""
An alternative version where we use a remote channel to communicate the results
diretectly from the workers. This seems to be less afficient than
`run_distributed_fetch`.
"""
function run_distributed_remotechannel()
    result_channel = Distributed.RemoteChannel(()->Channel(buffer_size))
    Distributed.@distributed for job_id in 1:N_jobs
        put!(result_channel, some_work_that_takes_time(job_id))
    end

    consume_unmanaged(result_channel, N_jobs)
end

#============================ multi-level parallelism =============================#

"""
Run on multiple workers but have only *one worker per node* and and achive
node-internal parallelism through threading.

NOTE: This actually taks more time than pure distributed code.
"""
function run_multilevel_parallel()
    result_channel = Distributed.RemoteChannel(()->Channel(buffer_size))

    # note: this does not consider the number of threads per node. Thus, it is
    # likely slower. Also coordinating on a single `result_channel` from many
    # threads may slow things down.
    Distributed.@distributed for job_id in 1:N_jobs
        Threads.@spawn put!(result_channel, some_work_that_takes_time(job_id))
    end

    consume_unmanaged(result_channel, N_jobs)
end

# This version seems better but does not run somehow.
# TODO: ask on discourse
function run_multilevel_parallel2()
    result_channel = Channel(buffer_size) do ch
        @sync for job_id in 1:N_jobs
            @async begin
                result = Distributed.@fetch begin
                    fetch(Threads.@spawn(some_work_that_takes_time(job_id)))
                end
                put!(ch, result)
            end
        end
    end

    consume(result_channel)
end
