using ThreadPools
using Base.Threads: nthreads

glibc_coreid() = @ccall sched_getcpu()::Cint
tglibc_coreid(i::Integer) = fetch(@tspawnat i glibc_coreid());

for i in 1:nthreads()
    println("Running on thread $i (glibc_coreid: $(tglibc_coreid(i)))")
end
