TIMEOUT= Dict{Any,Any}("ACCEPT"=>0.1,
                       "ACCEPT_data"=>1,
                       "RECEIVE"=>0.01,
                       "RECEIVE_data"=>1,
                       "OFFLINE_CHECKPOINT"=>5,
                       "OFFLINE_THRESHOLD"=>30000,
                       "pending_Calc_Threshold"=>30,
                       "ONLINE_REPORT_TIMER"=>1000);

NETWORK=Dict{Any,Any}("server_IP"=>"192.168.1.70", # server IP address
                      "msgPort"=>4001,            # msg port
                      "dataPort"=>4002);          # data port

USER=Dict{Any,Any}("username"=>"User002",
                   "password"=> "123456",
                   "taskID"=>"t001");             # current task

# get local data
X=readcsv("/VERTICOX/Source/Estimation/Client2/uaru2.txt"); #covariate
beta1b=readcsv("/VERTICOX/Source/Estimation/Client2/para2.txt"); #model parameter
M = size(X,2);
LOCALDATA=Dict{Any,Any}("X"=>X[:,1:M-2],
                        "T"=>X[:,M-1],
                        "Delta"=>X[:,M],
                        "beta1b"=>beta1b[1:M-2]
                        );
LOCALDATA["CovX"] = LOCALDATA["X"]'*LOCALDATA["X"];

## create matlab pool
if nprocs()<2
  addprocs(1)
end
include("newMSGListener-2.jl")
include("newJobListener-2.jl")

## start calculation
tic()
output = newMSGListener(TIMEOUT, NETWORK, USER, LOCALDATA);
toc()
