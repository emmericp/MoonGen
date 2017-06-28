return function(env)
  env.arp = function(ip, timeout)
    ip = ip or 5; timeout = timeout or 5
    if type(ip) == "number" then
      return {"arpRequest", timeout = ip}
    else
      return {"arpRequest", ip = ip, timeout = timeout}
    end
  end
end
