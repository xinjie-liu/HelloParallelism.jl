# Note: This script contains asynchronous green threading routines (tasks on a
# single thread) as well as shared-memory paralellisim (traditional
# multi-threading). There is also multi-process (workers/nodes) paralellisim via the
# `Distributed` package but I did not have the time to include it here. The Channels
# use will need to be a little bit different in that case. I in the context of
# `Distributed` one would need to use `RemoteChannel` et al.

import Primes

const N_runs = 30
const buffer_size = 100
const consumer_sleep_time = 0.1

#====================== dumme work that we want to get done =======================#
function some_work_that_takes_time(ch::Channel, id)
    #    println("Started work for job $id on thread $(Threads.threadid())")
    # sleep for some time (up to 1 second)
    # compute some random stuff
    result = Primes.prime(5*99999)
    # post the result on the channel.
    put!(ch, (;result, id, threadid=Threads.threadid()))
end

function consume(ch::Channel)
    for result in ch
        println(result)
        # lets assume there is some heavy post processing here
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
            @async some_work_that_takes_time(ch, id)
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
            some_work_that_takes_time(ch, id)
        end
        println("joined again")
    end

    # the for-loop automatically takes from `result_channel` until the task bound
    # the channel above finished. So no need to count here.
    consume(result_channel)
end
