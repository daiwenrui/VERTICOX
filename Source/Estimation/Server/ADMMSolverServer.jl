@everywhere function checkCoxDataSync(result, msg)
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
    println("Number of samples does not match");
    res = false;
  else
    println("Number of samples validated");
  end

  return result, res;
end

@everywhere function initCoxSolver(result)
  # N: number of samples, M: total number of features
  N = result["num_samples"];
  K = result["num_sites"];
  # T: tied times
  T = result["T"];
  # Delta: event observed or at risk
  Delta = result["Delta"];

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

  # Indices for observed event and event at risk
  DeltaIdx = Delta .== 1;
  IdxInTime = zeros(D, 1);
  DI = zeros(D, 1);
  for kk = 1:D
    T_idx = T .== Tuniq[kk];
    Observed = T_idx & DeltaIdx;
    DI[kk, 1] = sum(Observed);
    IdxInTime[kk] = sum(T_idx);
  end
  IdxInTime = cumsum([0; IdxInTime[1:end-1]])+1;
  T2obs = zeros(N, 1);
  for kk=1:D-1
    T2obs[IdxInTime[kk]:IdxInTime[kk+1]-1,1]=kk;
  end
  T2obs[IdxInTime[D]:N,1]=D;

  result["DI"] = DI;
  result["TU"] = T2obs;
  result["z_old"] = zeros(N,K)-1;
  result["z_new"] = zeros(N,K);
  result["zbar_new"] = zeros(N,1);
  result["gamma_old"] = zeros(N,K);
  result["gamma_new"] = zeros(N,K);
  result["betaX"] = zeros(N,K);
  result["idxInTime"] = IdxInTime;

  return result;
end

@everywhere function ADMMCoxSolverServer(result)
  # Initialize parameters for ADMM
  IdxInTime = result["idxInTime"];
  DI = result["DI"];
  T2obs = result["TU"];
  K = result["num_sites"];
  N = result["num_samples"];
  gamma_old = result["gamma_new"][:,:];
  gamma_new = gamma_old;
  z_old = result["z_new"][:,:];
  z_new = z_old-1;
#  zbar_new = ones(N,1);
  zbar_new = result["zbar_new"];
  rho = 1.0;
  # Cox model under ADMM
  Site_Result = result["betaX"][:,:];

  # Step 2: Update zbar
  # Aggregate results from K sites
  AggrResult = sum(Site_Result,2)/K;
  gamma_bar = sum(gamma_old,2)/K;
  # Solve zbar with Newton-Raphson method
  z_iter = 0;
  zbar_old = zeros(N,1)-1;

  epsilon = 1e-5;
  while (sum(abs(zbar_new-zbar_old))>epsilon && z_iter<1500)
    z_iter = z_iter+1;
    zbar_old = zbar_new;
    zexp = exp(K*zbar_old);
    zexp_d1 = K*zexp;
    # First derivatives of f(zbar)
    CumRisk = cumsum(zexp[end:-1:1]);
    CumRisk = flipdim(CumRisk,1);
    CumRisk = CumRisk[IdxInTime];
    CumRisk1 = DI./CumRisk;
    CumRisk1 = cumsum(CumRisk1,1);
    SubCumRisk1 = CumRisk1[T2obs];
    SubCumRisk1 = SubCumRisk1.*zexp_d1;
    df1 = SubCumRisk1+K*rho*(zbar_old-AggrResult-gamma_bar/rho);
    # Second derivatives of f(zbar)
    CumRisk2 = DI./(CumRisk.*CumRisk);
    CumRisk2 = cumsum(CumRisk2,1);
    SubCumRisk2 = CumRisk2[T2obs];
    SubCumRiskRep2 = repmat(SubCumRisk2,1,N);
    df2 = triu(SubCumRiskRep2,0)+tril(SubCumRiskRep2',-1);
    df2 = K*(diagm(SubCumRisk1[:,1])+rho*eye(N))-df2.*(zexp_d1*zexp_d1');
    zbar_new = zbar_old-df2\df1;
    zbar_diff = sum(abs(zbar_new-zbar_old));
  end
  # Update z
  z_new = repmat(zbar_new,1,K)+Site_Result-repmat(AggrResult,1,K)+(gamma_old-repmat(gamma_bar,1,K))/rho;
  # Step 3: Update gamma
  gamma_new = repmat(gamma_bar+rho*(AggrResult-zbar_new),1,K);
  result["z_new"] = z_new;
  result["gamma_new"] = gamma_new;
  result["zbar_new"] = zbar_new;

  return result;
end
