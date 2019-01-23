# getipaddr()
NETWORK=Dict{Any,Any}("server_IP"=>"192.168.1.70", # server IP address
                      "msgPort"=>4001,            # msg port
                      "dataPort"=>4002)           # data port

num_users = 2;
users = cell(num_users,7);
users[1,:] = ["u001"  "User001"   0  true   now()  true  "123456"]; #user 1
users[1,3] = cell(0);
users[2,:] = ["u002"  "User002"   0  true   now()  true  "123456"]; #user 2
users[2,3] = cell(0);
#users[3,:] = ["u003"  "User003"   0  true   now()  true  "123456"]; #user 3
#users[3,3] = cell(0);

jobs= cell(num_users,4);
jobs[1,:] = ["t001"  "u001"  false  0];
jobs[2,:] = ["t001"  "u002"  false  0];
#jobs[3,:] = ["t001"  "u003"  false  0];
jobs[1,4] = cell(0);
jobs[2,4] = cell(0);
#jobs[3,4] = cell(0);

currentTask = cell(1,5);
currentTask = ["t001"  "VERTICOX" 0  9  0]; # current task
currentTask[3]=cell(0);
currentTask[5]=cell(0);

shutdown_job = ["shutdown"  "u005"  false];

DB=Dict{Any,Any}("users"=>users,
                 "jobs"=>jobs,
                 "shutdown_job"=>shutdown_job,
                 "currentTask"=>currentTask,
                 "joined_count"=>0,
                 "joined_count_data"=>0,
                 "isActive"=>false);
TIMEOUT= Dict{Any,Any}("ACCEPT"=>0.1,
                       "ACCEPT_data"=>1,
                       "RECEIVE"=>0.01,
                       "RECEIVE_data"=>1,
                       "OFFLINE_CHECKPOINT"=>5,
                       "OFFLINE_THRESHOLD"=>30000,
                       "pending_Calc_Threshold"=>30);
MSG_CODEBOOK=Dict{Any,Any}("break"=>0,
                           "create_Lab_Connection"=>1,
                           "add_socks_list"=>2,
                           "confirm_new_client"=>3,
                           "confirm_online_client"=>4,
                           "confirm_online_clientFromDatalistener"=>5,
                           "closeServerByClient"=>6,
                           "remove_socks_list"=>7,
                           "getNewData"=>8,
                           "sendNewData"=>9,
                           "updateCalculation"=>10,
                           "updateCalculation_Done"=>11,
                           "updateCalculation_Fail"=>12,
                           "stopCalculation"=>13,
                           "pauseCalculation"=>14,
                           "checkClient"=>15,
                           "receiveClient2ServerData"=>16);
ParaInServer=Dict{Any,Any}("rho"=>1.0,
                           "lambda"=>0.0,
                           "maxit"=>5000,  # max number of iteration
                           "tol"=>1e-7);   # error tolerance

#add processors
if nprocs()<2
  addprocs(1)
end
include("newClientListener.jl")
include("newDataListener.jl")

#main loop
tic()
output = newClientListener(TIMEOUT, MSG_CODEBOOK, NETWORK, DB, ParaInServer);
toc()
println("The task is done!");
