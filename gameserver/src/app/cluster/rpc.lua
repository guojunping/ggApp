rpc = rpc or {}

function rpc.init()
    rpc.reload()
    -- 开启集群
    local serverid = skynet.getenv("id")
    local cluster_port
    if skynet.getenv("area") == "dev" then
        cluster_port = tonumber(skynet.getenv("cluster_port")) or serverid
    else
        cluster_port = serverid
    end
    cluster.open(cluster_port)
end

function rpc.reload()
    -- 优先使用nodes中提供的集群配置
    local nodes = skynet.getenv("nodes") or {}
    rpc.node_address = {}
    for node_name,conf in pairs(nodes) do
        rpc.node_address[node_name] = conf.address
    end
    if next(rpc.node_address) then
        cluster.reload(rpc.node_address)
    else
        cluster.reload()
    end
end

local MAINSRV_NAME=".main"

function rpc.dispatch(session,source,SOURCE,cmd,...)
    local request = {...}
    logger.logf("debug","cluster","op=recv,session=%s,source=%s,SOURCE=%s,cmd=%s,request=%s",
        session,source,SOURCE,cmd,request)
    _G.SOURCE = SOURCE
    local handler = rpc.CMD[cmd]
    local response
    if handler then
        response = {xpcall(handler,gg.onerror,...)}
    else
        response = {false,"no handler"}
    end
    _G.SOURCE = nil
    if session ~= 0 then
        local isok = table.remove(response,1)
        logger.logf("debug","cluster","op=resp,session=%s,source=%s,SOURCE=%s,cmd=%s,request=%s,response=%s,isok=%s",
            session,source,SOURCE,cmd,request,response,isok)
        if isok then
            skynet.retpack(table.unpack(response))
        else
            skynet.response()(false)
        end
    end
end


rpc.CMD = rpc.CMD or {}
function rpc.register(cmd,handler)
    rpc.CMD[cmd] = handler
end

rpc.register("exec",function (method,...)
    return gg.exec(_G,method,...)
end)

rpc.register("execcode",gg.execcode)


rpc.register("playerexec",function (pid,method,...)
    local player = playermgr.getplayer(pid)
    if player then
        return gg.exec(player,method,...)
    end
end)

--- call方式rpc调用,如果调用失败则报错
--@param[type=string|table] node 节点名
--@param[type=string] cmd 指令名
--@param ... 指令参数
--@return 执行指令返回的结果
function rpc.call(node,cmd,...)
    local address
    if type(node) == "string" then
        address = MAINSRV_NAME
    else
        address = node.address
        node = node.node
    end
    assert(node,"nil-node")
    assert(address,"nil-address")
    local SOURCE = {
        node = skynet.getenv("id"),
        address = skynet.self(),
        call = true,
    }
    local request = {...}
    logger.logf("debug","cluster","op=call,node=%s,address=%s,SOURCE=%s,cmd=%s,request=%s",
        node,address,SOURCE,cmd,request)
    local response = {cluster.call(node,address,"cluster",SOURCE,cmd,...)}
    logger.logf("debug","cluster","op=return,node=%s,address=%s,SOURCE=%s,cmd=%s,request=%s,response=%s",
        node,address,SOURCE,cmd,request,response)
    return table.unpack(response)
end

function rpc.pcall(node,cmd,...)
    return pcall(rpc.call,node,cmd,...)
end

function rpc.xpcall(node,cmd,...)
    return xpcall(rpc.call,gg.onerror,node,cmd,...)
end

--- send方式rpc调用,不等待,不关心对方返回结果
--@param[type=string|table] node 节点名
--@param[type=string] cmd 指令名
--@param ... 指令参数
function rpc.send(node,cmd,...)
    local address
    if type(node) == "string" then
        address = MAINSRV_NAME
    else
        address = node.address
        node = node.node
    end
    assert(node,"nil-node")
    assert(address,"nil-address")
    local SOURCE = {
        node = skynet.getenv("id"),
        address = skynet.self(),
    }
    local request = {...}
    logger.logf("debug","cluster","op=send,node=%s,address=%s,SOURCE=%s,cmd=%s,request=%s",
        node,address,SOURCE,cmd,request)
    return cluster.send(node,address,"cluster",SOURCE,cmd,...)
end

function __hotfix(module)
    rpc.reload()
    logger.logf("info","cluster","op=cluster.reload")
end

return rpc
