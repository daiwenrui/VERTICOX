@everywhere function AUCComputeClient(result, LOCALDATA)
  beta = LOCALDATA["beta1b"];
  lp_mean = mean(LOCALDATA["X"],1)*beta;
  result["betaX"] = LOCALDATA["X"]*beta-lp_mean[1];
  result["betaX_new"] = LOCALDATA["Xnew"]*beta-lp_mean[1];

  return result;
end
