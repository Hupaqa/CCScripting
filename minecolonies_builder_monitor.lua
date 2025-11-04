-- Monitor + MineColonies work order materials display for Advanced Peripherals (ComputerCraft)

local term = term
local peripheral = peripheral
local textutils = textutils

-- helper: safe call if method exists
local function safeCall(per, name, ...)
    if not per or type(per[name]) ~= "function" then return nil, "no_method" end
    local ok, res = pcall(per[name], per, ...)
    if not ok then return nil, res end
    return res
end

-- find a monitor, prefer a wrapped peripheral named "monitor"
local function getMonitor()
    local mon = peripheral.find("monitor")
    if not mon then
        -- try scanning all peripherals for type "monitor"
        for _, pName in ipairs(peripheral.getNames()) do
            local t = peripheral.getType(pName)
            if t == "monitor" then
                mon = peripheral.wrap(pName)
                break
            end
        end
    end
    return mon
end

-- find a MineColonies/Advanced Peripheral-like peripheral by looking for common method names
local function findMineColoniesPeripheral()
    local candidates = {}
    local wantMethods = {
        "getWorkOrders", "getWorkOrder", "getWorkOrderRequirements", "getRequirements", "getMaterials",
        "getBuildingWorkOrders", "getBuildings", "getBuilding"
    }
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name)
        local ok = false
        for _, m in ipairs(wantMethods) do
            for _, pm in ipairs(methods) do
                if pm == m then ok = true; break end
            end
            if ok then break end
        end
        if ok then
            table.insert(candidates, name)
        end
    end

    if #candidates == 0 then
        -- fallback: return first peripheral that has any of the methods when wrapped (try a few)
        for _, name in ipairs(peripheral.getNames()) do
            local wrapped = peripheral.wrap(name)
            local methods = peripheral.getMethods(name)
            for _, m in ipairs(wantMethods) do
                for _, pm in ipairs(methods) do
                    if pm == m then
                        return wrapped, name
                    end
                end
            end
        end
        return nil, nil
    end

    -- prefer the first candidate
    local chosenName = candidates[1]
    return peripheral.wrap(chosenName), chosenName
end

-- draw lines on monitor safely
local function printToMonitor(mon, lines)
    if not mon then
        print("No monitor attached. Output to terminal:")
        for _, l in ipairs(lines) do print(l) end
        return
    end

    -- set up monitor
    local w, h = mon.getSize()
    -- some monitors don't support setTextScale; don't overwrite method if absent
    -- prepare wrapped lines so long text will flow to next monitor row instead of truncating
    local function wrapLine(str, width)
        str = tostring(str or "")
        if width <= 0 then return {str} end
        local out = {}
        while #str > 0 do
            if #str <= width then
                table.insert(out, str)
                break
            end
            -- try to break at last space within width
            local sub = str:sub(1, width)
            local splitAt
            for i = #sub, 1, -1 do
                if sub:sub(i,i):match("%s") then
                    splitAt = i
                    break
                end
            end
            if splitAt and splitAt > 1 then
                table.insert(out, (sub:sub(1, splitAt-1)))
                -- trim leading spaces from remainder
                str = str:sub(splitAt+1)
            else
                -- no space found, hard break
                table.insert(out, sub)
                str = str:sub(width+1)
            end
        end
        return out
    end

    local wrapped = {}
    for _, l in ipairs(lines) do
        local wlines = wrapLine(l, w)
        for _, wl in ipairs(wlines) do table.insert(wrapped, wl) end
    end

    mon.clear()
    mon.setCursorPos(1,1)
    for row = 1, h do
        local text = wrapped[row] or ""
        -- ensure we don't write past edge; mon.write may keep cursor, so set pos each time
        if #text > w then text = text:sub(1, w) end
        mon.setCursorPos(1, row)
        mon.write(text)
    end
end

-- attempt multiple possible API signatures to obtain work orders and requirements
local function getBuilderWorkOrderRequirements(peripheralWrapper)
    -- try to get buildings and pick a builder building if present
    local buildings, err = safeCall(peripheralWrapper, "getBuildings")
    local buildingId
    if buildings and type(buildings) == "table" then
        for _, b in ipairs(buildings) do
            -- heuristics: structure type or role may include "builder"
            if (b.type and tostring(b.type):lower():find("builder")) or (b.role and tostring(b.role):lower():find("builder")) then
                buildingId = b.id or b.uuid or b.name or b.position or b.index
                break
            end
        end
    end

    -- if we didn't get a builder building, let user choose from getBuildings list or ask for id
    if not buildingId and buildings and type(buildings) == "table" and #buildings > 0 then
        -- pick first by default
        buildingId = buildings[1].id or buildings[1].uuid or buildings[1].name or 1
    end

    -- attempt several methods to get work orders
    local workOrders
    local tryList = {
        function() return safeCall(peripheralWrapper, "getBuildingWorkOrders", buildingId) end,
        function() return safeCall(peripheralWrapper, "getWorkOrders", buildingId) end,
        function() return safeCall(peripheralWrapper, "getWorkOrders") end,
        function() return safeCall(peripheralWrapper, "getWorkOrder", buildingId) end
    }

    for _, try in ipairs(tryList) do
        local res, e = try()
        if res and type(res) == "table" then
            workOrders = res
            break
        end
    end

    -- If workOrders is a single work order table rather than a list, normalize
    if workOrders and not workOrders[1] and type(workOrders) == "table" then
        -- maybe it's a single work order or a map
        local t = {}
        table.insert(t, workOrders)
        workOrders = t
    end

    if not workOrders then
        return nil, "no_workorders", { buildings = buildings, err = err }
    end

    -- pick first active or first entry
    local selected = workOrders[1]
    for _, wo in ipairs(workOrders) do
        if wo.status and tostring(wo.status):lower():find("active") then
            selected = wo
            break
        end
    end

    -- try to get requirements from workorder object if present
    if selected and selected.requirements and type(selected.requirements) == "table" then
        return selected.requirements, nil, { workOrder = selected }
    end

    -- try peripheral methods that return requirements
    local reqMethods = {
        function() return safeCall(peripheralWrapper, "getWorkOrderRequirements", selected.id or selected.uuid or buildingId) end,
        function() return safeCall(peripheralWrapper, "getRequirements", selected.id or selected.uuid or buildingId) end,
        function() return safeCall(peripheralWrapper, "getMaterials", selected.id or selected.uuid or buildingId) end,
        function() return safeCall(peripheralWrapper, "getWorkOrderMaterials", selected.id or selected.uuid or buildingId) end
    }

    for _, f in ipairs(reqMethods) do
        local res, e = f()
        if res and type(res) == "table" then
            return res, nil, { workOrder = selected }
        end
    end

    return nil, "no_requirements", { workOrder = selected }
end

-- format requirements table into printable lines
local function formatRequirements(req)
    local lines = {}
    table.insert(lines, "Materials required:")
    if not req or next(req) == nil then
        table.insert(lines, "  (none or unknown format)")
        return lines
    end

    -- expected formats:
    -- 1) list of {name = "minecraft:stone", count = 64}
    -- 2) list of {item = {id="minecraft:stone"}, count = 64}
    -- 3) map name->count
    for i, v in ipairs(req) do
        if type(v) == "table" then
            local name = v.name or (v.item and (v.item.name or v.item.id)) or v.id or v.key
            local count = v.count or v.amount or v.qty or v.quantity
            name = tostring(name or ("item"..(i)))
            count = tostring(count or "?")
            table.insert(lines, string.format("  - %s : %s", name, count))
        else
            table.insert(lines, "  - " .. tostring(v))
        end
    end

    -- if table was a map (non-array)
    if #req == 0 then
        for k, v in pairs(req) do
            table.insert(lines, string.format("  - %s : %s", tostring(k), tostring(v)))
        end
    end

    return lines
end

-- Main
local function main()
    local mon = getMonitor()
    local mcPeripheral, mcName = findMineColoniesPeripheral()

    if not mcPeripheral then
        local lines = {
            "MineColonies peripheral not found.",
            "Peripherals found: " .. textutils.serialize(peripheral.getNames()),
            "Make sure Advanced Peripherals addon for MineColonies is attached.",
            "Script will print debug data to terminal."
        }
        printToMonitor(mon, lines)
        print(textutils.serialize(peripheral.getNames()))
        return
    end

    local lines = { "Using MineColonies peripheral: " .. tostring(mcName) }
    printToMonitor(mon, lines)

    local reqs, err, debug = getBuilderWorkOrderRequirements(mcPeripheral)
    if not reqs then
        local out = {
            "Could not determine requirements.",
            "Error: " .. tostring(err),
            "Debug: " .. textutils.serialize(debug)
        }
        printToMonitor(mon, out)
        return
    end

    local formatted = formatRequirements(reqs)
    printToMonitor(mon, formatted)
end

main()