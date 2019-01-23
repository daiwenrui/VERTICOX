include("ADMMSolverClient.jl")

@everywhere global sock_newJobListener

@everywhere function newJobListener(NETWORK)
  global sock_newJobListener;
  sock_newJobListener = connect(NETWORK["server_IP"],NETWORK["dataPort"]);

  if isopen(sock_newJobListener)
    println("Job Listener is ready");
    return true;
  else
    return false;
  end
end

@everywhere function closeJobListener()
  global sock_newJobListener;

  close(sock_newJobListener);
end

@everywhere function receiveData()
  global sock_newJobListener;
  data = deserialize(sock_newJobListener);

  return data;
end

@everywhere function sendData(data)
  global sock_newJobListener;

  serialize(sock_newJobListener,data);
end

@everywhere function updateResults(CODEBOOK, result, LOCALDATA, NETWORK, CTIMER)
  global sock_newJobListener;
  result["error"] = false;
  resultFromServer = deserialize(sock_newJobListener);

  if isempty(resultFromServer)
    result["error"] = true;
    println("Error: cannot get message from server");
    return result;
  else
    t_tmp = time()-resultFromServer["datatime"];
    println("Time for receiving data is ", t_tmp);
    CTIMER["rece"] += t_tmp;
    if resultFromServer["tag"] != CODEBOOK["getNewData"];
      result["error"] = true;
      println("get unkonwn message");
      return result;
    end
    result["iter"] = resultFromServer["iter"];
    result["z"] = resultFromServer["z"];
    result["gamma"] = resultFromServer["gamma"];
    result["rho"] = resultFromServer["rho"];

#    println("Receive data from Data Server: ", NETWORK["server_IP"], ":", NETWORK["dataPort"]);
    println("Start updating at iter : ",result["iter"]);
    t_tmp = time();
    result = ADMMCoxSolverClient(result, LOCALDATA);
    t_tmp = time()-t_tmp;
    println("Time for calculation is ", t_tmp);
    CTIMER["calc"] += t_tmp;
    #final result
    aaa = Dict{Any,Any}("tag"=>CODEBOOK["receiveClient2ServerData"],
                        "betaX"=>result["betaX"],
                        "iter"=>result["iter"],
                        "datatime"=>time());
    res = serialize(sock_newJobListener, aaa);
    t_tmp = time()-aaa["datatime"];
    println("Time for sending results is ", t_tmp);
    CTIMER["send"] += t_tmp;
    if res == -1
      println("fail to upload results to server");
    else
      println("Finish updating at iter : ",result["iter"]," and send results to ", NETWORK["server_IP"], ":", NETWORK["dataPort"]);
    end
  end

  return result, CTIMER;
end
