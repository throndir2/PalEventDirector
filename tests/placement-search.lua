return function(test, equal, truthy)
    local Search = require("ped.placement_search")
    local Config = require("ped.config")

    local function search(allow, preferred)
        return Search.new({origin={X=10000,Y=-20000,Z=45000},range=5000,slot=1,rotation=20,
            preferred=preferred,allowFallback=allow})
    end

    test("placement search keeps a successful approach and does not inspect in-base candidates", function()
        local runner=search(true,{X=12000,Y=-20000,Z=45000})
        local calls=0
        local function check(position,mode)
            calls=calls+1
            equal(mode,"approach")
            return {ready=true,position=position}
        end
        local result=runner:poll(check,2)
        equal(result.mode,"approach"); equal(result.fallbackReason,nil); equal(calls,1)
        equal(runner:poll(check,2).ready,true); equal(calls,1)
    end)

    test("sky-base fallback uses bounded same-height candidates after an unreachable approach", function()
        local runner=search(true,{X=12000,Y=-20000,Z=45000})
        local calls=0
        local function check(position,mode)
            calls=calls+1
            if mode=="approach" then return {ready=false,reason="path-unreachable"} end
            equal(position.Z,45000)
            truthy((position.X-10000)^2+(position.Y+20000)^2 <= 1000^2+0.001)
            if calls<4 then return {ready=false,reason="no-solid-surface"} end
            return {ready=true,position=position}
        end
        local result=runner:poll(check,2)
        equal(result.pending,true); equal(calls,2)
        result=runner:poll(check,2)
        equal(result.ready,true); equal(result.mode,"in-base")
        equal(result.fallbackReason,"path-unreachable"); equal(result.attempts,4)
    end)

    test("placement search exhausts its bounded surface candidates without widening or fabricating a spawn", function()
        local runner=search(true,nil)
        local calls=0
        local function check(position)
            calls=calls+1
            equal(position.Z,45000)
            return {ready=false,reason="water-or-unsupported-surface"}
        end
        local result
        for _=1,8 do result=runner:poll(check,2) end
        equal(result.ready,false); equal(result.pending,nil); equal(calls,16)
        runner:poll(check,2); equal(calls,16)
    end)

    test("placement fallback can be disabled and validates the configuration flag", function()
        local runner=search(false,{X=12000,Y=-20000,Z=45000})
        local calls=0
        local result=runner:poll(function()
            calls=calls+1
            return {ready=false,reason="path-unreachable"}
        end,2)
        equal(result.pending,nil); equal(result.ready,false); equal(calls,1)
        local config=Config.defaults()
        equal(config.customAssault.allowInBaseFallback,true)
        config.customAssault.allowInBaseFallback=false
        truthy(Config.validate(config))
        config.customAssault.allowInBaseFallback="true"
        equal(Config.validate(config),false)
    end)

    test("a fault during placement consumes the attempt and prevents any later query", function()
        local runner=search(true,nil)
        local calls=0
        local function check()
            calls=calls+1
            error("fixture native boundary")
        end
        equal(pcall(runner.poll,runner,check,2),false)
        equal(pcall(runner.poll,runner,check,2),false)
        equal(calls,1)
    end)
end
