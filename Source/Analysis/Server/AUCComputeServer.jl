@everywhere function checkCoxDataSync(result, msg)
  println("checkCoxDataSync");
  res = true;
  if isempty(result["T"])
    result["T"] = msg["T"];
  elseif result["T"]!=msg["T"]
    println("Time-to-event not synchronized");
    res = false;
  else
    println("Time-to-event validated");
  end
  if isempty(result["Delta"])
    result["Delta"] = msg["Delta"];
  elseif result["Delta"]!=msg["Delta"]
    println("Censoring data not synchronized");
    res = false;
  else
    println("Censoring data validated");
  end
  if result["num_samples"]==0
    result["num_samples"] = msg["num_samples"];
  elseif result["num_samples"]!=msg["num_samples"]
    println("Number of training samples does not match");
    res = false;
  else
    println("Number of training samples validated");
  end
  if result["num_samples_new"]==0
    result["num_samples_new"] = msg["num_samples_new"];
  elseif result["num_samples_new"]!=msg["num_samples_new"]
    println("Number of testing samples does not match");
    res = false;
  else
    println("Number of testing samples validated");
  end

  return result, res;
end

@everywhere function initCoxSolver(result)
  println("initCoxSolver");
  # N: number of training samples, M: total number of features
  N = result["num_samples"];
  # K: number of sites
  K = result["num_sites"];
  # T: tied times
  T = result["T"];
  # Delta: event observed or at risk
  Delta = result["Delta"];
  # N_new: number of testing samples
  N_new = result["num_samples_new"];

  # Server replaces the time ticks with only one observation.
  Tuniq = unique(T);
  D = length(Tuniq);
  for kk = 1:D
    T_idx = find(T == Tuniq[kk]);
    if(length(T_idx) == 1)
      if(T_idx == 1)
        T[T_idx] = T[T_idx + 1];
      else
        T[T_idx] = T[T_idx - 1];
      end
    end
  end

  result["betaX"] = zeros(N,K);
  result["betaX_new"] = zeros(N_new,K);
  result["Tevt"] = Tuniq;
  result["jobDone"] = false;

  return result;
end

@everywhere function rcmp_TW(x, y, nalast)
  nax = isnan(x);
  nay = isnan(y);
  if nax && nay
    return 0;
  end
  if nax
    return nalast?1:-1;
  end
  if nay
    return nalast?-1:1;
  end
  if x<y
    return -1;
  end
  if x>y
    return 1;
  end
  return 0;
end
@everywhere function SurvAnalysisServer(result)
  betaX = result["betaX"][:,:];
  betaX_new = result["betaX_new"][:,:];
  N = result["num_samples"];
  N_new = result["num_samples_new"];
  Delta = result["Delta"];
  T = result["T"];
  Tuniq = result["Tevt"];
  D = size(Tuniq,1);
  T_idx = zeros(D,1);
  D_num = zeros(D,1);

  for k=1:D
    D_idx = find(T.==Tuniq[k]);
    T_idx[k] = minimum(D_idx);
    Evt_idx = find(Delta[D_idx].==1);
    D_num[k] = size(Evt_idx,1);
  end
  lp = sum(betaX,2);
  lp_new = sum(betaX_new,2);
  lp_mean = mean(lp);
  lp = lp-lp_mean;
  lp_new = lp_new-lp_mean;
  lp_exp = exp(lp);
  lp_new_exp = exp(lp_new);
  lp_sum = flipdim(cumsum(flipdim(lp_exp,1),1),1);
  lp_sum = lp_sum[T_idx];
  R = D_num./lp_sum;
  R = cumsum(R,1);
  SurvCurve = exp(-1*R*lp_new_exp');
  result["Surv"] = SurvCurve;

  return result;
end
@everywhere function AUCComputeServer(result)
  println("AUCComputerServer");
  result["jobDone"] = true;
  betaX = result["betaX"][:,:];
  betaX_new = result["betaX_new"][:,:];
  N = result["num_samples"];
  N_new = result["num_samples_new"];
  Delta = result["Delta"];
  T = result["T"];
  lp = sum(betaX,2);
  lpnew = sum(betaX_new,2);
  lp_mean=mean(lp);
  lp=lp-lp_mean;
  R=flipdim(exp(lp),1);
  R=cumsum(R);
  R=flipdim(R,1);
  n_event=zeros(N,1);
  diff_time=zeros(N,1);
  diff_time[1]=1;
  n_event[1]=Delta[1];
  time0=T[1];
  j=2;
  for i=2:N
    n_event[j]=n_event[j]+Delta[i];
    if abs(time0-T[i])>0
      diff_time[i]=1;
      time0=T[i];
      j=j+1;
    end
  end
  k=1;
  for i=1:N
    if diff_time[i]>0
        R[k]=n_event[k]/R[i];
        T[k]=T[i];
        k=k+1;
    end
  end
  R[1:k-1]=cumsum(R[1:k-1]);
  j=1;
  for i=1:k-1
    if n_event[i]>0
        R[j]=-1*R[i];
        T[j]=T[i];
        j=j+1;
    end
  end
  n_t=j-1;
  lpnew=exp(lpnew-lp_mean);
  surv=exp(R[1:n_t]*lpnew');
  utimes=T[1:n_t];
  nevent=n_event[1:n_t];
  th_time=1:600;
  N_th_time=length(th_time);
  surv_new=zeros(N_th_time,N_new);
  for k = 1:N_new
    for j=1:N_th_time
      optim=true;
      for i=n_t:-1:1
        if optim && th_time[j]>=T[i]
          surv_new[j,k]=surv[i,k];
          optim=false;
        end
      end
      if optim
        surv_new[j,k]=1;
      end
    end
  end
  sumf=mean(surv_new,2);
  factor1=(1-sumf).*sumf;
  EW=zeros(N_th_time,1);
  idx=(repmat(lpnew,1,N_new)-repmat(lpnew',N_new,1)).>0;
  for k=1:N_th_time
    EW_tmp = sum(sum((1-surv_new[k,:])'*surv_new[k,:].*idx,2),1);
    EW[k]=EW_tmp[1,1];
  end
  AUC=EW./(factor1*N_new*N_new);
  AUC[isnan(AUC).==1]=0;
  result["AUC"]=AUC;

  return result;
end
