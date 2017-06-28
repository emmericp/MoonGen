return function(env, flows)
  function env.Flow(tbl)
    local name = tbl[1]
    local flow = {}
    for i = 2, #tbl do
      flow[i - 1] = tbl[i]
    end
    flows[name] = flow
  end
end
