-- Monitor + MineColonies work order materials display for Advanced Peripherals (ComputerCraft)
local term = rawget(_G, "term")
local peripheral = rawget(_G, "peripheral")
local textutils = rawget(_G, "textutils")

--
-- minecolonies_builder_monitor.lua
-- Simplified monitor that uses Advanced Peripherals' getWorkOrderResources
-- Assumptions: The MineColonies/AdvancedPeripherals peripheral exposes
-- the method getWorkOrderResources(...). This script first tries
-- calling getWorkOrderResources() with no args. If that returns nil,
-- it will attempt to find a work order id via getWorkOrders() and
-- call getWorkOrderResources(id). Output is printed to a wrapped CC
-- monitor if available, otherwise to the terminal.
--

-- helper: safe call if method exists
local function safeCall(per, name, ...)
    if not per then return nil, "no_peripheral" end
    local methods = peripheral.getMethods and peripheral.getMethods(peripheral.getName and peripheral.getName(per) or "")
    -- If wrapped object has method, call it, otherwise try pcall access
    if type(per[name]) ~= "function" then
        return nil, "no_method"
    end
    local ok, res = pcall(per[name], per, ...)
    if not ok then return nil, res end
    return res
end

-- find a monitor peripheral (wrapped)
local function getMonitor()
    local mon = peripheral.find and peripheral.find("monitor")
    if mon then return mon end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            return peripheral.wrap(name)
        end
    end
    return nil
end

-- find a peripheral that exposes getWorkOrderResources
local function findResourcesPeripheral()
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name) or {}
        for _, m in ipairs(methods) do
            if m == "getWorkOrderResources" then
                return peripheral.wrap(name), name
            end
        end
    end
    -- fallback: try to wrap first peripheral and test method existence
    for _, name in ipairs(peripheral.getNames()) do
        local wrapped = peripheral.wrap(name)
        if wrapped and type(wrapped.getWorkOrderResources) == "function" then
            return wrapped, name
        end
    end
    return nil, nil
end

-- write lines to monitor, wrapping by width; if no monitor, print to terminal
local function printToMonitor(mon, lines)
    if not mon then
        for _, l in ipairs(lines) do print(l) end
        return
    end

    local w, h = mon.getSize()
    local function wrapLine(str)
        str = tostring(str or "")
        if w <= 0 then return {str} end
        local out = {}
        while #str > 0 do
            if #str <= w then table.insert(out, str); break end
            local sub = str:sub(1, w)
            local splitAt
            for i = #sub, 1, -1 do
                if sub:sub(i, i):match("%s") then splitAt = i; break end
            end
            if splitAt and splitAt > 1 then
                table.insert(out, sub:sub(1, splitAt-1))
                str = str:sub(splitAt+1)
            else
                table.insert(out, sub)
                str = str:sub(w+1)
            end
        end
        return out
    end

    local wrapped = {}
    for _, l in ipairs(lines) do
        for _, part in ipairs(wrapLine(l)) do table.insert(wrapped, part) end
    end

    mon.clear()
    mon.setCursorPos(1, 1)
    for row = 1, h do
        local text = wrapped[row] or ""
        if #text > w then text = text:sub(1, w) end
        mon.setCursorPos(1, row)
        mon.write(text)
    end
end

-- Try to obtain resources using getWorkOrderResources only (preferred)
local function getResources(per)
    -- 1) try calling without args
    local res, err = safeCall(per, "getWorkOrderResources")
    if res and type(res) == "table" and next(res) ~= nil then
        return res, nil
    end

    -- 2) try to find a work order id and call with that id
    local wos = safeCall(per, "getWorkOrders")
    if wos and type(wos) == "table" and #wos > 0 then
        -- pick active if present; also remember numeric index
        local chosen = wos[1]
        local chosenIndex = 1
        for i, wo in ipairs(wos) do
            if wo.status and tostring(wo.status):lower():find("active") then chosen = wo; chosenIndex = i; break end
        end

        -- Prefer calling with numeric index (many AP integrations expect a number)
        if chosenIndex and type(chosenIndex) == "number" then
            local res2, err2 = safeCall(per, "getWorkOrderResources", chosenIndex)
            if res2 and type(res2) == "table" and next(res2) ~= nil then
                return res2, nil
            end
        end

        -- If numeric attempt failed, try known id fields but ensure we don't pass a table
        local idCandidate = chosen.id or chosen.uuid or chosen.workOrderId or chosen.name
        if idCandidate and type(idCandidate) ~= "table" then
            local res3, err3 = safeCall(per, "getWorkOrderResources", idCandidate)
            if res3 and type(res3) == "table" and next(res3) ~= nil then
                return res3, nil
            else
                return nil, err3 or "no_resources_returned"
            end
        end
    end

    return nil, err or "no_resources"
end

-- Format resources into printable lines. Supports several shapes:
--  - array of {item = {id=...} or name=..., count=...}
--  - array of {name=..., count=...}
--  - map of name->count
local function formatResources(res)
    local lines = {"Materials required:"}
    if not res or next(res) == nil then
        table.insert(lines, "  (none or unknown format)")
        return lines
    end

    -- if array-like
    if #res > 0 then
        for i, v in ipairs(res) do
            if type(v) == "table" then
                local name = v.name or (v.item and (v.item.id or v.item.name)) or v.id or v.key
                local count = v.count or v.amount or v.qty or v.quantity
                name = tostring(name or ("item" .. i))
                count = tostring(count or "?")
                table.insert(lines, string.format("  - %s : %s", name, count))
            else
                table.insert(lines, "  - " .. tostring(v))
            end
        end
        return lines
    end

    -- otherwise treat as map
    for k, v in pairs(res) do
        table.insert(lines, string.format("  - %s : %s", tostring(k), tostring(v)))
    end
    return lines
end

-- Main
local function main()
    local mon = getMonitor()
    local per, name = findResourcesPeripheral()
    if not per then
        local out = {
            "MineColonies resources peripheral not found.",
            "Peripherals: " .. textutils.serialize(peripheral.getNames()),
            "Ensure Advanced Peripherals (colony integrator) is attached."
        }
        printToMonitor(mon, out)
        return
    end

    local header = {"Using peripheral: " .. tostring(name)}
    printToMonitor(mon, header)

    local res, err = getResources(per)
    if not res then
        printToMonitor(mon, {"Could not get resources:", tostring(err)})
        return
    end

    local lines = formatResources(res)
    printToMonitor(mon, lines)
end

main()