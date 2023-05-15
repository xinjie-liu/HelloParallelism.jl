function some_work_that_takes_time(id; provoke_threadunsafe=true)
    result = 0

    rng = StableRNGs.StableRNG(id)

    for i = 1:100_000
        result += rand(rng, Bool)
    end

    unsafe_result = provoke_threadunsafe ? do_threadunsafe_work(id) : nothing

    (; result, id, thread_id=Threads.threadid(), workder_id=Distributed.myid(), unsafe_result)
end

function do_threadunsafe_work(id)
    rng = StableRNGs.StableRNG(id)
    d = [3, 3, 3, 3, 3, 3]
    N = 6
    cost_tensors = [randn(rng, d...) for i = 1:N]
    solution = TensorGames.compute_equilibrium(cost_tensors)
    solution.x |> sum |> sum
end
