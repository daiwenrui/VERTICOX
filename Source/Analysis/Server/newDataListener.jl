include("AUCComputeServer.jl")
@everywhere global socks_list_data = Dict{Any,Any}("socks"=>[],
                                                   "client_iter"=>[],
                                                   "username"=>cell(0),
                                                   "numSample"=>[],
                                                   "numSampleNew"=>[],
                                                   "betaX"=>[],
                                                   "betaX_new"=>[],
                                                   "isOffline"=>falses(0),
                                                   "isReceived"=>falses(0));
@everywhere global srvsock_data

@everywhere function newDataListener(NETWORK)
  global srvsock_data;

  srvsock_data = listen(NETWORK["dataPort"]);
  println("Server socket data established at ", now()," from port:", NETWORK["dataPort"]);
end

@everywhere function handleIncomingMessageFromClient(result, MSG_CODEBOOK, TIMEOUT, DB, STIMER)
  global socks_list_data;
  msg_res=[];
  msgout=[];

  isClientsReceived = (sum(socks_list_data["isReceived"])==result["num_sites"] && DB["isActive"]);
  for i = 1: length(socks_list_data["socks"])
    if (!socks_list_data["isReceived"][i]) || (isClientsReceived && !result["clientCount"][i])
#      println("ready for socks ", i);
      msg = deserialize(socks_list_data["socks"][i]);
      socks_list_data["isReceived"][i] = true;
    else
      msg = -1;
    end
    if msg != -1
      if msg["tag"] == MSG_CODEBOOK["confirm_new_client"]
        socks_list_data["username"][i] = msg["username"];
        if !(msg["username"] == "UCSD_SHUTDOWN")
          # initialization
          result, res = checkCoxDataSync(result,msg);
          if !res
            println("Error: Time-to-event or censoring data not matched");
          end
        end
        println("    >>>>New user: ", msg["username"], " ( count: ", length(socks_list_data["username"]),", confirmed at ", msg["datatime"], " from socket: ", i);
        # modified from newDataListener
        msgout=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_online_clientFromDatalistener"],
                             "username"=> msg["username"],
                             "ID"=> i);
      elseif msg["tag"]== MSG_CODEBOOK["receiveClient2ServerData"]
        println("Receiving data from ", socks_list_data["username"][i]);
        result["clientCount"][i] = true;
        result["betaX"][:,i] = msg["betaX"];
        result["betaX_new"][:,i] = msg["betaX_new"];
      else
        println("error: Unknown incoming message detected from user ", socks_list_data["username"][i]);
      end
    end
  end
  if !isempty(socks_list_data["username"]) && (sum(true .== result["clientCount"]) == length(socks_list_data["username"]))
    msg_res = Dict{Any,Any}("tag"=>MSG_CODEBOOK["updateCalculation"]);
    result["clientCount"] = falses(result["num_sites"]);
#    println("all incoming messages has been collected from clients");
  end

  return result, msg_res, msgout, STIMER
end

@everywhere function add_socket_list(msg, old_socks_size, TIMEOUT, MSG_CODEBOOK)
  global srvsock_data;
  global socks_list_data;
  msgout = [];
  socks_list_length = msg["length"];
  if old_socks_size - socks_list_length != -1
    println(2, "There is an error between data and client listeners");
    msgout=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_online_clientFromDatalistener"], "username"=>[], "ID"=>socks_list_length);
  else
    tmp_sock = accept(srvsock_data);
    serialize(tmp_sock, MSG_CODEBOOK);
    println("    >>>>a new client (not confirmed) has been received by newDataListener: ", old_socks_size+1);
    old_socks_size = old_socks_size + 1;
    socks_list_data["socks"] = vcat(socks_list_data["socks"],tmp_sock);
    socks_list_data["username"] = vcat(socks_list_data["username"], cell(1));
    socks_list_data["isReceived"] = vcat(socks_list_data["isReceived"],false);
    println("addOneClient data username: ", socks_list_data["username"]);
  end
  return old_socks_size, msgout;
end

@everywhere function  updateAllSites(msg, msgminus1, result, MSG_CODEBOOK, TIMEOUT, ParaInServer, STIMER)
  global socks_list_data;

#  println("updateAllSites data username: ", socks_list_data["username"]);
  if haskey(msg,"DB") && !isvalidUsers(socks_list_data, msg)
    println("error: One or more users are not ready for update");
    msgout = -1;
  else
    if isempty(result["betaX"]) || isempty(result["betaX_new"])
      result = initCoxSolver(result);
#      println("update all sites");
    else
      result = SurvAnalysisServer(result);
      result = AUCComputeServer(result);
    end
    result, msgout, STIMER = sendoutMessage(msgminus1, result, socks_list_data, MSG_CODEBOOK, TIMEOUT, ParaInServer, STIMER);
  end
  println("Update All Sites");
  return result, msgout, STIMER
end

@everywhere function  sendoutMessage(msgminus1, result, socks_list_data, MSG_CODEBOOK, TIMEOUT, ParaInServer, STIMER)
  println("ready to send message to clients");
  msgout=Dict{Any,Any}("tag"=>MSG_CODEBOOK["sendNewData"]);
  if msgminus1 == -1
    println("client is not ready for accepting message");
    # send message to client listener.
    msgout["tag"]=MSG_CODEBOOK["updateCalculation_Fail"];
    return result, msgout;
  end
  for i = 1: length(socks_list_data["username"])
    # send updated result back to clients
    a = Dict{Any,Any}("tag"=>MSG_CODEBOOK["getNewData"],
                      "datatime"=>time());
    res = serialize(socks_list_data["socks"][i], a);
    if res == -1
      println("Cannot send message to user : ", socks_list_data["username"][i]);
    else
      println("Results have been sent to user : ", socks_list_data["username"][i]);
    end
  end
  # send message to client listener.
  if result["jobDone"]
    msgout["tag"] = MSG_CODEBOOK["updateCalculation_Done"];
  end

  return result, msgout, STIMER
end

@everywhere function isvalidUsers(socks_list_data, msg)
  res = false;
  if !msg["DB"]["isActive"]
    println("Detect: DB is inActive");
    return res;
  end
  for i = 1: length(socks_list_data["socks"])
    aa = getUserIDByName(socks_list_data["username"][i], msg["DB"]);
    pos = find((aa.== msg["DB"]["jobs"][:,2]) .== true);
    if (length(pos) != 1) || (!msg["DB"]["jobs"][pos,3][1])
      println("Detect: inActive user <$pos>");
      return res
    end
  end
  res = true;

  return res
end

@everywhere function getUserIDByName(username, DB)
    userID = cell(0);
    pos1 = find((username.== (DB["users"][:, 2])) .== true); # 2 is for username
    if !isempty(pos1)
        userID = DB["users"][pos1, 1];
    end
  return userID
end

@everywhere function remove_socks_list(offline_idx, MSG_CODEBOOK)
  global socks_list_data;

  if !isempty(offline_idx) && max(offline_idx) <= length(socks_list_data["socks"]);
    println("The following clients have been offline: ", socks_list_data["socks"](offline_idx));
    for i = 1: length(offline_idx)
      closeRemoteSocket(socks_list_data["socks"][offline_idx[i]],  MSG_CODEBOOK);
    end
    socks_list_data["socks"][offline_idx] = [];
  end
  old_socks_size = length(socks_list_data["socks"]);

  return old_socks_size
end

@everywhere function closeServerData(ServerName, MSG_CODEBOOK)
  global srvsock_data;
  global socks_list_data;

  num_users = length(socks_list_data["socks"]);
  for i = 1:num_users
    closeRemoteSocket(socks_list_data["socks"][i],  MSG_CODEBOOK);
  end
  close(srvsock_data);
  println("Server socket data closed at ", now());
  println(num_users, " clients has been disconnected");
end

@everywhere function closeRemoteSocketData(sock,  MSG_CODEBOOK)
  a = Dict{Any,Any}("tag"=> MSG_CODEBOOK["break"]);
  res = serialize(sock, a);
#  if res != -1
#    println("send shutdown signal to ", sock);
#  else
  if res == -1
    println("fail to send shutdown signal");
  end
  close(sock);

  return res
end
