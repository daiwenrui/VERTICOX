function newMSGListener(TIMEOUT, NETWORK, USER, LOCALDATA)
  CTIMER=Dict{Any,Any}("calc"=>0,
                      "rece"=>0,
                      "send"=>0);
  tic()
  sock_newMSGListener = connect(NETWORK["server_IP"],NETWORK["msgPort"]); # connect to newMSGListener
  if isopen(sock_newMSGListener)
    isMsgConnected = true;
    println("Msg Listener is ready");
  else
    isMsgConnected = false;
  end
  isJobConnected = remotecall_fetch(2,newJobListener,NETWORK);
  if isMsgConnected && isJobConnected
    println("ready to receive the MSG_CODEBOOK from Server via msg port!!:")
    MSG_CODEBOOK = deserialize(sock_newMSGListener); # get acknowledgments from newMSGListener;
    println("Finished!!!")
    println("ready to receive the CODEBOOK from Server via data port!!:")
    CODEBOOK = remotecall_fetch(2,receiveData);
    println("Finished!!!")
    if !isempty(MSG_CODEBOOK) && !isempty(CODEBOOK)
      num_samples = size(LOCALDATA["X"],1);
      Para=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_new_client"],
                         "datatime"=>now(),
                         "username"=>USER["username"],
                         "password"=>USER["password"],
                         "taskID"=>USER["taskID"],
                         "T"=>LOCALDATA["T"],
                         "Delta"=>LOCALDATA["Delta"],
                         "num_samples"=>num_samples);
      serialize(sock_newMSGListener, Para);
      remotecall(2,sendData,Para);
      println("connection between server @newJobListener has been established");
      println("waiting for authorization from server");

      msg = deserialize(sock_newMSGListener);
      if msg["tag"] != -1
        println("connection between server@newMSGListener has been established");
      else
        error(msg["msg"]);
      end
    else
      error("connection lost from newMSGListener\n");
      error("connection lost from newJobListener\n");
    end
  else
    error("Cannot connect to server@newMSGListener\n");
    error("Cannot connect to server@newJobListener\n");
  end
  itime = toc();

  closeClientFlag = false;
  result=Dict{Any,Any}("error"=>false, "iter"=>0, "z"=>cell(0), "gamma"=>cell(0));
  h = now();
  server_timeStamp = now();
  while !closeClientFlag
#    println("Receive msg from Msg Server: ", NETWORK["server_IP"], ":", NETWORK["msgPort"]);
    try
      msg = deserialize(sock_newMSGListener)
    catch
      break;
    end
    if !isempty(msg)
      if msg["tag"] == MSG_CODEBOOK["break"]
        println("get shutdown signal");
        msgdata = remotecall_fetch(2,receiveData);
        break;
      elseif  msg["tag"] ==  MSG_CODEBOOK["getNewData"]
#        println("remote server requested to send data to here");
        result, CTIMER = remotecall_fetch(2, updateResults, CODEBOOK, result, LOCALDATA, NETWORK, CTIMER);
      elseif  msg["tag"] ==  MSG_CODEBOOK["confirm_online_client"]
        server_timeStamp = now();
      else
        println("Unknown message type received from server sock_newMSGListener");
        println("Unknown message type received from server sock_newJobListener");
      end
    end
    # report status to server.
    if TIMEOUT["ONLINE_REPORT_TIMER"] < Int64((now()-h))/1000########
      println("send confirm_online_client flag to ClientListener");
      msg=Dict{Any,Any}("tag"=>MSG_CODEBOOK["confirm_online_client"]);
      res = serialize(sock_newMSGListener, msg);
      if res == -1 || (TIMEOUT["OFFLINE_THRESHOLD"] < Int64((now()-server_timeStamp))/1000)  ########
        println("cannot connect to server");
        msg["tag"] = MSG_CODEBOOK["break"]
        println("close connection in Job");
        break
      end
      h = now();
    end
  end
  close(sock_newMSGListener);
#  println("    >>>>newMSGListener has been distroyed");
  remotecall(2,closeJobListener);
#  println("    >>>>newJobListener has been distroyed");
  println("Model parameters are ", result["beta"]);
  println("Actual model parameters are ", LOCALDATA["beta1b"]);
  println("Difference is ", result["beta"]-LOCALDATA["beta1b"]);
  println("SAD is ", sumabs(result["beta"]-LOCALDATA["beta1b"]), "; MAD is ", maxabs(result["beta"]-LOCALDATA["beta1b"]));
  println("Avg Time for receiving results is ", CTIMER["rece"]/result["iter"]);
  println("Avg Time for calculating results is ", CTIMER["calc"]/result["iter"]);
  println("Avg Time for sending results is ", CTIMER["send"]/result["iter"]);

  return result;
end
