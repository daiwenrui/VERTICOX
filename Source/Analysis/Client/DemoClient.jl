TIMEOUT= Dict{Any,Any}("ACCEPT"=>0.1,
                       "ACCEPT_data"=>1,
                       "RECEIVE"=>0.01,
                       "RECEIVE_data"=>1,
                       "OFFLINE_CHECKPOINT"=>5,
                       "OFFLINE_THRESHOLD"=>30000,
                       "pending_Calc_Threshold"=>30,
                       "ONLINE_REPORT_TIMER"=>1000);

NETWORK=Dict{Any,Any}("server_IP"=>"192.168.1.70",
                      "msgPort"=>4001,
                      "dataPort"=>4002);

USER=Dict{Any,Any}("username"=>"UCSD001",
                   "password"=> "123456",
                   "taskID"=>"t001");
# get local data
X = readcsv("C:/VERTICOX/Source/Analysis/Client/uaru1.txt");
Xnew =readcsv("C:/VERTICOX/Source/Analysis/Client/uaru1_test.txt");
beta1b = readcsv("C:/VERTICOX/Source/Analysis/Client/para1.txt");
M = size(X,2);
LOCALDATA=Dict{Any,Any}("X"=>X[:,1:M-2],
                        "Xnew"=>Xnew[:,1:M-2],
                        "T"=>X[:,M-1],
                        "Delta"=>X[:,M],
                        "beta1b"=>beta1b[1:M-2]);

## create matlab pool
if nprocs()<2
  addprocs(1)
end
include("newMSGListener.jl")
include("newJobListener.jl")

## start calculation
tic()
output = newMSGListener(TIMEOUT, NETWORK, USER, LOCALDATA);
toc()
println("The task is done!");
