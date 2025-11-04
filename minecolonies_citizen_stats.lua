-- minecolonies_citizen_stats.lua
-- Display MineColonies citizen happiness on a ComputerCraft/Advanced Peripherals monitor.
-- Behavior:
--  - Finds a peripheral exposing citizen data (tries common method names like getCitizens, getCitizensByTown, getCitizensList)
--  - Finds a monitor peripheral and prints each citizen name and happiness percentage
--  - Attempts to scale text to fit the monitor: decreases text scale until all lines fit vertically and horizontally
--  - Falls back to terminal output when no monitor is available
--  - Optional refresh loop can be enabled by setting REFRESH_INTERVAL > 0

local raw_term = rawget(_G, "term")
local peripheral = rawget(_G, "peripheral")
local textutils = rawget(_G, "textutils")
local os = rawget(_G, "os")

local REFRESH_INTERVAL = 0 -- seconds; set >0 to auto-refresh

local function safeCall(per, name, ...)
    if not per then return nil, "no_peripheral" end
    if type(per[name]) ~= "function" then return nil, "no_method" end
    local ok, res = pcall(per[name], per, ...)
    if not ok then return nil, res end
    return res
end

local function findMonitor()
    if peripheral and peripheral.find then
        local m = peripheral.find("monitor")
        if m then return m end
    end
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "monitor" then
            return peripheral.wrap(n)
        end
    end
    return nil
end

local function findCitizenPeripheral()
    local candidates = {"getCitizens", "getCitizensList", "getCitizensByTown", "getCitizensByColony", "getCitizensData"}
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name) or {}
        for _, m in ipairs(methods) do
            for _, want in ipairs(candidates) do
                if m == want then
                    return peripheral.wrap(name), name, m
                end
            end
        end
    end
    -- fallback: try wrapping and probing common names
    for _, name in ipairs(peripheral.getNames()) do
        local w = peripheral.wrap(name)
        if w then
            for _, want in ipairs(candidates) do
                if type(w[want]) == "function" then return w, name, want end
            end
        end
    end
    return nil, nil, nil
end

local function extractCitizenList(raw)
    -- Accept many formats: array of {name=..., happiness=...}, map, nested structures
    if not raw then return {} end
    if type(raw) ~= "table" then return {} end

    -- If array-like
    if #raw > 0 then
        local out = {}
        for _, v in ipairs(raw) do
            if type(v) == "table" then
                local name = v.name or v.displayName or v.username or v.uuid or v.id
                local happy = v.happiness or v.happinessLevel or v.satisfaction or v.mood
                table.insert(out, { name = tostring(name or "<unknown>"), happiness = happy })
            else
                table.insert(out, { name = tostring(v), happiness = nil })
            end
        end
        return out
    end

    -- If map: iterate and try to pull fields
    local out = {}
    for k, v in pairs(raw) do
        if type(v) == "table" then
            local name = v.name or v.displayName or v.username or k
            local happy = v.happiness or v.happinessLevel or v.satisfaction or v.mood
            table.insert(out, { name = tostring(name or k), happiness = happy })
        else
            table.insert(out, { name = tostring(k), happiness = v })
        end
    end
    return out
end

local function formatLines(citizens)
    local lines = {}
    table.insert(lines, "Citizens - Happiness")
    table.insert(lines, string.rep("-", 20))
    for _, c in ipairs(citizens) do
        local h = c.happiness
        local hs = (h == nil) and "?" or (type(h) == "number" and (math.floor(h*100 + 0.5) .. "%") or tostring(h))
        table.insert(lines, string.format("%s : %s", c.name, hs))
    end
    return lines
end

local function writeToMonitor(mon, lines)
    if not mon then
        for _, l in ipairs(lines) do print(l) end
        return
    end

    local w, h = mon.getSize()
    -- Try text scaling: CC monitors support setTextScale on some versions
    local setTextScale = mon.setTextScale
    local getTextScale = mon.getTextScale

    -- Determine max needed rows
    local neededRows = #lines

    local triedScales = {1, 0.75, 0.5, 0.4, 0.33, 0.25}
    local chosenScale = nil
    for _, s in ipairs(triedScales) do
        if setTextScale then
            pcall(setTextScale, mon, s)
        end
        local cw = math.floor(w / (s)) -- approximate char width
        local ch = math.floor(h / (s)) -- approximate char height
        -- crude check: assume each line occupies 1 char-row
        if neededRows <= ch then
            chosenScale = s
            break
        end
    end

    -- If we couldn't set scale or none fit, leave as default
    if chosenScale and setTextScale then pcall(setTextScale, mon, chosenScale) end

    mon.clear()
    mon.setCursorPos(1,1)
    for i = 1, h do
        local text = lines[i] or ""
        if #text > w then text = text:sub(1, w) end
        mon.setCursorPos(1, i)
        mon.write(text)
    end
end

local function mainOnce()
    local mon = findMonitor()
    local per, name, method = findCitizenPeripheral()
    if not per then
        local out = {"Citizen peripheral not found.", "Peripherals: " .. textutils.serialize(peripheral.getNames())}
        writeToMonitor(mon, out)
        return
    end

    local raw, err = safeCall(per, method)
    if not raw then
        writeToMonitor(mon, {"Could not read citizens: ", tostring(err)})
        return
    end

    local citizens = extractCitizenList(raw)
    table.sort(citizens, function(a,b) return (a.name or "") < (b.name or "") end)
    local lines = formatLines(citizens)
    writeToMonitor(mon, lines)
end

local function main()
    if REFRESH_INTERVAL and REFRESH_INTERVAL > 0 then
        while true do
            mainOnce()
            os.sleep(REFRESH_INTERVAL)
        end
    else
        mainOnce()
    end
end

main()
