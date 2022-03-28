wget https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.5-linux-x86_64.tar.gz
tar -xvzf julia-1.6.5-linux-x86_64.tar.gz
echo "alias julia='~/julia-1.6.5/bin/julia'" >> ~/.bashrc
source ~/.bashrc

git clone https://github.com/lamps-co/PMParallelRoutine.git
cd PMParallelRoutine
git checkout pmap
git submodule update --init
cd powerflowmodule.jl
git checkout parallel_tests
cd ..
julia --project
