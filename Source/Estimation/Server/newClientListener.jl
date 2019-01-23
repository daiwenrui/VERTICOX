function newClientListener(TIMEOUT, MSG_CODEBOOK, NETWORK, DB, ParaInServer)
  closeServerFlag = false;
  socks_list=Dict{Any,Any}("socks"=>cell(0),
                           "isConfirmed"=>[],
                           "timeStamp"=>[],
                           "username"=>[],
                           "isOffline"=>falses(0));
  old_socks_size = 0;
  result=Dict{Any,Any}("clientCount"=>falses(size(DB["users"],1)),
                       "iter"=>0,
                       "lambda"=>ParaInServer["lambda"],
                       "rho"=>ParaInServer["rho"],
                       "error"=>[],
                       "jobDone"=>false,
                       "num_samples"=>0,
                       "num_sites"=>size(DB["users"],1),
                       "T"=>[],
                       "Delta"=>[],
                       "z_new"=>[],
                       "z_old"=>[],
                       "gamma_new"=>[],
                       "gamma_old"=>[],
                       "betaX"=>[]);
  STIMER = Dict{Any,Any}("rece"=>zeros(size(DB["users"])),
                        "calc"=>0,
                        "send"=>zeros(size(DB["users"])));
  # msg listen
  srvsock = listen(NETWORK["msgPort"]);
  println("Server socket established at ", now()," from port:", NETWORK["msgPort"]);
  # data listen
  remotecall(2,newDataListener,NETWORK);
  #println("New Data listener is ready..");
  println("Waiting for client's connection...");

  h = now()
  msgminus1 = 1;
  while !closeServerFlag
#    println("Still in while block:",!closeServerFlag)
    result, msg, msgout, STIMER = remotecall_fetch(2,handleIncomingMessageFromClient,result,MSG_CODEBOOK,TIMEOUT,DB, STIMER)
    socks_list, closeServerFlag, DB, result, msgout, STIMER = checkMessageFromsocks_list(closeServerFlag, socks_list, TIMEOUT, MSG_CODEBOOK, DB, msg, msgout, msgminus1, result, STIMER);
    DB, msgminus1,closeServerFlag = asyncCheckMessageFromDataListener(closeServerFlag, msgout, socks_list, TIMEOUT, MSG_CODEBOOK, DB);
    socks_list, old_socks_size, msgout = addOneClientIntoNewSockets_list(srvsock, socks_list, TIMEOUT, DB, MSG_CODEBOOK, old_socks_size,msgout);
    socks_list, old_socks_size, h, DB = removeOfflineSockets_list(h, socks_list, TIMEOUT,MSG_CODEBOOK, DB, old_socks_size);
  end
  output = Dict{Any,Any}("result"=>result);
#  println("send shutdown signal to data listener");
#  println("waiting for data listener to be closed");
  println("shutdown signal received");
#  println("data listener has been closed");
  sendBreakMsg(srvsock, socks_list, MSG_CODEBOOK);
  println("Avg time for calculation is ", STIMER["calc"]/result["iter"]);
  for i=1:result["num_sites"]
    println("Avg time for receiving results from ", socks_list["username"][i], " is ", STIMER["rece"][i]/result["iter"]);
    println("Avg time for sending results to ", socks_list["username"][i], " is ", STIMER["send"][i]/result["iter"]);
  end
  return output
end

# function checkMessageFromsocks_list(closeServerFlag, socks_list, socks_list_data, TIMEOUT, MSG_CODEBOOK, DB, msg, msgout,msgminus1, result)
function checkMessageFromsocks_list(closeServerFlag, socks_list, TIMEOUT, MSG_CODEBOOK, DB, msg, msgout,msgminus1, result, STIMER)
  msg_list = cell(length(socks_list["socks"]));
  for i = 1:length(socks_list["socks"])
    if !socks_list["isConfirmed"][i]
      msg_list[i] = deserialize(socks_list["socks"][i]);
#      println("Deserialize from socks ",i, " username: ", msg_list[i]["username"]);
#      println("Finish deserializing!")
    else
      msg_list[i] = -1;
    end
  end
  for i = 1:length(socks_list["socks"])
    if msg_list[i] != -1
      if msg_list[i]["tag"] == MSG_CODEBOOK["confirm_new_client"]
        socks_list, DB= addsocks_list(i, socks_list, msg_list[i], MSG_CODEBOOK, DB, msgout);
#        println("checkMessage: new socks ", i, DB["joined_count"], DB["joined_count_data"]);
      elseif  msg_list[i]["tag"] == MSG_CODEBOOK["confirm_online_client"]
        if socks_list["isConfirmed"][i]
          socks_list["timeStamp"][i] = now();
        end
        a=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_online_client"]);
        serialize(socks_list["socks"][i], a);
        # println("checkMessage: online socks ", i);
      elseif  msg_list[i]["tag"] == MSG_CODEBOOK["closeServerByClient"]
        if socks_list["isConfirmed"][i]
          closeServerFlag = true;
        end
      else
        println("Unknown message type received from client ",socks_list["socks"][i]);
      end
    end
  end

  if !isempty(msg)
    if msg["tag"]==MSG_CODEBOOK["updateCalculation"]
      if !result["jobDone"]
        println("Update calculation at iter: ", result["iter"]+1);
        result, msgout, STIMER = remotecall_fetch(2, updateAllSites, msg, msgminus1, result, MSG_CODEBOOK, TIMEOUT, ParaInServer, STIMER);
      else
        println("Calculation is paused, sicne it has converged");
      end
    elseif msg["tag"]==MSG_CODEBOOK["break"]
      println("shutdown signal received");
      closeServerFlag = true;
    elseif msg["tag"]==MSG_CODEBOOK["pauseCalculation"]
      println("Calculations is pause, since one or more offline users detected");
    else
      println("Unrecognized msg received");
    end
  end
  # send start calculation signal.
  if DB["joined_count"] == size(DB["jobs"], 1) && DB["joined_count_data"] == size(DB["jobs"], 1)
    if !DB["isActive"]
      DB["isActive"] = true;
      # modified from newDatalistener
      if !result["jobDone"]
        println("Update calculation at iter: ", result["iter"]+1);
        msg=Dict{Any,Any}("tag"=>MSG_CODEBOOK["updateCalculation"],"DB"=>DB);
        result, msgout, STIMER = remotecall_fetch(2, updateAllSites, msg, msgminus1, result, MSG_CODEBOOK, TIMEOUT, ParaInServer, STIMER);
      else
        println("Calculation is paused, sicne it has converged");
      end
    end
  else
    if DB["isActive"]
      # send pending signal;
      DB["isActive"] = false;
      # modified from newDatalistener
      msg = Dict{Any,Any}("tag"=>MSG_CODEBOOK["pauseCalculation"],"DB"=>DB);
      println("Calculation is paused, sicne one or more offline users detected");
    end
  end

  return socks_list, closeServerFlag, DB, result, msgout, STIMER
end

function addsocks_list(i, socks_list, msg_list, MSG_CODEBOOK, DB, msgout)
  isValidUser, idx, isShutdown = isValidConnection(msg_list, DB);
  idx=idx[1];

  if !isValidUser
    socks_list["isOffline"][i] = true;  # force this client offline;
    socks_list["isConfirmed"][i] = false; # mark it as unconfirmed;
    msg = string("    >>>>New user rejected (invalid Username or pswd or TaskID) at ", msg_list["datatime"]," from socket: ",socks_list["socks"][i]);
    a=Dict{Any,Any}("tag"=> -1,"msg"=>msg);
    serialize(socks_list["socks"][i], a); # tell client authorization error;
    println(msg);
    return socks_list, DB;
  end

  if !isShutdown && !DB["jobs"][idx, 3]
    DB["jobs"][idx, 3] = true;
    DB["joined_count"] = DB["joined_count"] + 1;
  else
    if isShutdown
      DB["shutdown_job"][1, 3] = true;
    else
      socks_list["isOffline"][i] = true;  # force this client offline;
      socks_list["isConfirmed"][i] = false; # mark it as unconfirmed;
      msg = string("    >>>>New user rejected (Duplicated session detected) at $msg_list.datatime from socket:",socks_list["socks"][i]);
      a=Dict{Any,Any}("tag"=> -1, "msg"=>msg);
      serialize(socks_list["socks"][i], a); # tell client authorization error;
      println(msg);
      return socks_list, DB;
    end
  end
  # handle system error. this will never happen.
  if DB["joined_count"] > size(DB["jobs"], 1)
    socks_list["isOffline"][i] = true;  # force this client offline;
    socks_list["isConfirmed"][i] = false; # mark it as unconfirmed;
    msg = string("    >>>>System Error, total joined_count is larger than the pool size of jobs at ",msg_list["datatime"], "   from socket: ", socks_list["socks"][i]);
    a=Dict{Any,Any}("tag"=> -1, "msg"=> msg);
    serialize(socks_list["socks"][i], a); # tell client authorization error;
    println(msg);
    return socks_list, DB;
  end
  # add new user
  msg="passed authorization";
  a=Dict{Any,Any}("tag"=> 1, "msg"=> msg);
  serialize(socks_list["socks"][i], a); # tell client authorization passed.
  println("     >>>>New user", msg_list["username"]," confirmed at ",msg_list["datatime"]," from socket: ", i);
  socks_list["timeStamp"][i] = now();  ##################
  if socks_list["isConfirmed"][i]
    println("     >>>>A duplicated confirmation detected at ",msg_list["datatime"], " from socket: ", socks_list[i]["socks"]);
  else
    socks_list["username"][i] = msg_list["username"];
#    println("checkMessage username: ", socks_list["username"]);
    socks_list["isConfirmed"][i] = true;
#    confirmation will be handled in asycn
  end
  return socks_list, DB
end

function isValidConnection(msg, DB)
  pos1 = find((msg["username"] .== DB["users"][:, 2]).==true); # 2 is for username ###########
  println("msg username is :",msg["username"], " and passw: ", DB["users"][pos1, 7])
  pos2 = find((msg["password"] .== DB["users"][pos1, 7]).==true); # 4 is for password
  pos3 = DB["users"][pos1, 1] .== DB["jobs"][:, 2]; # find all index of tasks that includes socks_list.socks (DB.users{pos1, 1})
  pos4 = msg["taskID"] .== DB["jobs"][:, 1];
  pos5 = find((pos3 & pos4).==true);
  # check if it is shut down signal
  pos6 = DB["users"][pos1, 1] .== DB["shutdown_job"][:, 2]; # find all index of tasks that includes socks_list.socks (DB.users{pos1, 1})
  pos7 = msg["taskID"] .== DB["shutdown_job"][:, 1];
  isShutdown = true in (pos6 & pos7);
  if ~isempty(pos1) && ~isempty(pos2) && ~isempty(pos5) || isShutdown
    res = true;
  else
    res = false;
  end

  return res, pos5, isShutdown
end

function asyncCheckMessageFromDataListener(closeServerFlag, msg, socks_list, TIMEOUT, MSG_CODEBOOK, DB)
  msgminus1=1;
  if !isempty(msg)
    if msg["tag"] == MSG_CODEBOOK["sendNewData"]
      msgminus1=tellClientToReceiveMessage(socks_list, TIMEOUT, MSG_CODEBOOK, DB);
    elseif msg["tag"] == MSG_CODEBOOK["updateCalculation_Done"]
      println("Finished ADMM update at iter : ", msg["iter"]);
      msgminus1 = -1;
    elseif msg["tag"] == MSG_CODEBOOK["updateCalculation_Fail"]
      println("Data listener failed to send message to client. please reconnect");
      msgminus1 = -1;
    elseif msg["tag"] == MSG_CODEBOOK["confirm_online_clientFromDatalistener"]
      if isempty(msg["username"])
        socks_list["isOffline"][msg["ID"]] = true;
        println("Data listener fail to add socks_list");
      else
        DB["joined_count_data"] = DB["joined_count_data"] + 1;
        println("Data listener has confirmed user ", msg["username"],"(DB.joind:", DB["joined_count"], " joined_data:", DB["joined_count_data"], " isactive:",DB["isActive"],")");
      end
    else
      println("Unknown message type received from client");
      msgminus1 = -1;
    end
  end
  if msgminus1 == -1
    closeServerFlag = true;
  end
  return DB, msgminus1, closeServerFlag;
end

function tellClientToReceiveMessage(socks_list, TIMEOUT, MSG_CODEBOOK, DB)
  msg = 1;
  for i = 1:length(socks_list["socks"])
    a=Dict{Any,Any}("tag"=>MSG_CODEBOOK["getNewData"]);
    res = serialize(socks_list["socks"][i], a);
    if res == -1
      msg = -1;
      println("Cannot send message to client ", socks_list["username"][i]);
    end
  end

  # send message to client listener.
  return msg;
end

function addOneClientIntoNewSockets_list(srvsock, socks_list, TIMEOUT, DB, MSG_CODEBOOK, old_socks_size, msgout)
  # get total number of current users
  num_users = length(socks_list["socks"]);
  isSockOpen = false;
#  println("num of users is ", num_users, " num of users in DB is ", size(DB["users"],1));
  # check if there is any new incoming client
  if num_users<size(DB["users"],1)
    tmp_sock = accept(srvsock); # timeout at 0.1 second.
    isSockOpen = isopen(tmp_sock);
  end
  if isSockOpen
    tmp_list = find(socks_list["socks"] .== tmp_sock);
    if isempty(tmp_list)
      # send MSG_CODEBOOK to the client.
      println("send MSG_CODEBOOK TO client!")
      serialize(tmp_sock,MSG_CODEBOOK);
      println("succeed sending MSG_CODEBOOK TO client!")
      println(">>>>New user (without confirmation) ", num_users+1," tries to connect server at ", now());
      # add new client into socks_list;
      socks_list["socks"]=vcat(socks_list["socks"],tmp_sock);
      # mark it as unconfirmed
      socks_list["isConfirmed"]= vcat(socks_list["isConfirmed"],false);
      socks_list["timeStamp"] = vcat(socks_list["timeStamp"], now());   ##########
      socks_list["isOffline"] = vcat(socks_list["isOffline"],false);
      socks_list["username"] = vcat(socks_list["username"],cell(1));
      println("addOneClient username: ", socks_list["username"]);
      msg = Dict{Any,Any}("length"=>length(socks_list["socks"]),"username"=>socks_list["username"]);
      old_socks_size, msgout = remotecall_fetch(2, add_socket_list, msg, old_socks_size, TIMEOUT, MSG_CODEBOOK);
      if old_socks_size != length(socks_list["socks"])
        println(2, "Cannot get connection between this client (", socks_list.socks[end], ") and the data listener, please retry");
        msgout=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_online_clientFromDatalistener"], "username"=>[], "ID"=>length(socks_list["socks"]));  # send back confirm to client listener;
      end
    else
      println(2, string("      >>>>Duplicated clients detected at ",now(), "from socket(s)",string(tmp_list)));
    end
  end
  # println("addOneClient msgout is ", msgout);

  return socks_list,old_socks_size,msgout
end

function removeOfflineSockets_list(h, socks_list, TIMEOUT, MSG_CODEBOOK, DB,old_socks_size)
  if TIMEOUT["OFFLINE_CHECKPOINT"] > Int64(now()-h)/1000
    return socks_list, old_socks_size, h, DB
  end

  tmp_isOffline = falses(length(socks_list["socks"]));
  for i = 1: length(socks_list["socks"])
    tmp_isOffline[i] = ((Int64(now()-socks_list["timeStamp"][i])/1000) > TIMEOUT["OFFLINE_THRESHOLD"]);
  end
  socks_list["isOffline"] = ((socks_list["isOffline"]) | tmp_isOffline);
  if  true in socks_list["isOffline"]    #sum(socks_list.isOffline) > 0
    println("The following clients are offline ", socks_list["socks"], ":", string(socks_list["username"][socks_list["isOffline"]]), string(socks_list["socks"][socks_list["isOffline"]]));
    offline_idx = find(socks_list["isOffline"] .== true);
    tmp_offline = find(socks_list["isOffline"] .== true);
    for i = 1: length(tmp_offline)
      DB = removerUserFromDB(socks_list["username"][tmp_offline[i]], DB);
      closeRemoteSocket(socks_list["socks"][tmp_offline[i]],  MSG_CODEBOOK);
    end
    socks_list = removeOfflineClient(socks_list);
    println("request remove in Data listener");
    ss = " ";
    if !isempty(offline_idx)
      ss = string("<$offline_idx>");
    end
    println("Try to remove offline list : ", ss);
    old_socks_size = remotecall_fetch(2, remove_socks_list, offline_idx, MSG_CODEBOOK);

  end
  h=now();

  return socks_list, old_socks_size, h, DB
end

function removerUserFromDB(username, DB)
  pos3 = find((getUserIDByName(username, DB).==DB["jobs"][:, 2]).==true); # find all index of tasks that includes socks_list.socks (DB.users{pos1, 1})
  if !isempty(pos3)
    println("user: $username has been marked as inactive in DB");
    DB["jobs"][pos3, 3] = false;
    DB["joined_count"] = DB["joined_count"] - 1;
    DB["joined_count_data"] = DB["joined_count_data"] - 1;
  end
  if DB["joined_count"] < 0
    DB["joined_count"] = 0;
    for i = 1: size(DB["jobs"], 1)
      DB["jobs"][i, 3] = false;
    end
    println("an error (Negative count) detected when remove a User from DB, DB have been reset");
  end
  if DB["joined_count_data"] < 0
    DB["joined_count_data"] = 0;
  end

  return DB
end

function getUserIDByName(username, DB)
  userID = cell(0);
  pos1 = find((username .== DB["users"][:, 2]).==true); # 2 is for username
  if !isempty(pos1)
    userID = vcat(userID, DB["users"][pos1, 1]);
  end

  return userID
end

function removeOfflineClient(socks_list)
  for i = 1:length(socks_list["username"])
    if socks_list["isOffline"][i]
      socks_list["socks"][i] = cell(0);
      socks_list["timeStamp"][i] = cell(0);
      socks_list["username"][i] = cell(0);
      socks_list["isConfirmed"][i] = cell(0);
      socks_list["isOffline"][i] = cell(0);
    end
  end

  return socks_list
end

# close
function sendBreakMsg(srvsock, socks_list,MSG_CODEBOOK)
  closeServer(srvsock, socks_list, "newClientListener", MSG_CODEBOOK);
  remotecall(2, closeServerData, "newDataListener", MSG_CODEBOOK);
end

function closeServer(srvsock, socks_list, ServerName, MSG_CODEBOOK)
  num_users = length(socks_list["socks"]);
  for i = 1:num_users
    closeRemoteSocket(socks_list["socks"][i],  MSG_CODEBOOK);
  end
  close(srvsock);
  println(ServerName, " Server socket closed at ",now(), " from port: ", srvsock);
  println(num_users, " clients has been disconnected from ", ServerName);
end

function closeRemoteSocket(sock,  MSG_CODEBOOK)
  a=Dict{Any,Any}("tag"=>MSG_CODEBOOK["break"]);
  res = serialize(sock, a);
  if res != -1
    println("send shutdown signal to ", sock);
  else
    println("fail to send shutdown signal to ", sock);
  end
  close(sock);

  return res
end
