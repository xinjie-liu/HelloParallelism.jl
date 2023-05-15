function some_work_that_takes_time(id)
    result = 0
    for i = 1:100_000
        result += rand(Bool)
    end
    (; result, id, thread_id=Threads.threadid(), workder_id=Distributed.myid())
end
