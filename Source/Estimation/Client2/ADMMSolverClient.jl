@everywhere function ADMMCoxSolverClient(result, LOCALDATA)
  ProdX = result["rho"]*LOCALDATA["CovX"];
  SumX = LOCALDATA["X"]'*(result["rho"]*result["z"]-result["gamma"]+LOCALDATA["Delta"]);
  beta = ProdX\SumX;
  result["betaX"] = LOCALDATA["X"]*beta;
  result["beta"] = beta;

  return result;
end
