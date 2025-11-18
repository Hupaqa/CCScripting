-- Testing Script

local colony = peripheral.find("colony_integrator")
local mon = peripheral.find("monitor")
local chatbox = peripheral.find("chat_box")
local meSystem = peripheral.find("me_bridge")
local inventoryManager = peripheral.find("inventory_manager")
local storage
local mon_size_x, mon_size_y
local tick = 0
MeSystemInfo = {
    crafting = {
        job = nil,
        craftsMissingInputs = {},
    }
}
VisualData = {
    display_monitor = nil,
    page_button_size_x = 5,
    window_pos_x = 10,
    window_pos_y = 10,
    x_touch = -1,
    y_touch = -1,
    key_event = {
        key_press = -1,
        is_held = false
    },
    page_scroll = {},
    scroll = 0,
    resourcesNeeded = {},
    workOrders = {},
    pageFunction = nil,
    pageFunctionList = nil,
    pageNumber = 1,
    pageSwapRequested = false,
    redrawSpeed = 0.1
}

--- Check Execution time of function
local function timeFunctionExecution(func, ...)
    local startTime = os.clock()
    local result = { func(...) }
    local endTime = os.clock()
    local executionTime = endTime - startTime
    print("Function executed in " .. tostring(executionTime) .. " sec.")
    return table.unpack(result)
end

local function printObjectVal(object, outputFileIo, nestingLevel)
    nestingLevel = nestingLevel or 0
    if type(object) ~= "table" then
        print("Provided object is not a table.")
        return
    end
    if outputFileIo then
        for key, value in pairs(object) do
            local tabs = ""
            for i = 1, nestingLevel do
                tabs = tabs .. "\t"
            end
            local text = tabs .. "Key: " .. tostring(key) .. " | Value: " .. tostring(value) .. "\n"
            outputFileIo:write( text )
            if type(value) == "table" then
                printObjectVal(value, outputFileIo, nestingLevel + 1)
            end
        end
        if outputFileIo and nestingLevel == 0 then
            outputFileIo:close()
        end
    else
        for key, value in pairs(object) do
            print( "Key: " .. tostring(key) .. " | Value: " .. tostring(value) )
        end
    end
end

local function printFunctionsFromObject(object, toFile, fileName)
    if type(object) ~= "table" then
        print("Provided object is not a table.")
        return
    end
    if toFile then
        local outputFile = io.open(fileName or "output.txt", "w")
        for key, value in pairs(object) do
            if type(value) == "function" and key ~= "cancel" then
                local valueFromCall = tostring(value())
                outputFile:write( "Function: " .. tostring(key) .. " | Return Value: " .. valueFromCall .. "\n" )
            end
        end
        outputFile:close()
    else
        for key, value in pairs(object) do  
            if type(value) == "function" then
                local valueFromCall = tostring(value())
                print( "Function: " .. tostring(key) .. " | Return Value: " .. valueFromCall )
            end
        end
    end
end

--- Work Order Resource Class
Resource = {}
Resource.__index = Resource
function Resource:create(o)
    local rsrc = {}
    if o == nil then
        o = {}
    end
    setmetatable(rsrc, Resource)
    rsrc.item = o.item or {}
    rsrc.available = o.available or 0
    rsrc.needs = o.needs or 0
    rsrc.status = o.status or nil
    rsrc.displayName = o.displayName or ""
    rsrc.delivering = o.delivering or 0
    return rsrc
end

function Resource:neededAmount()
    return self.needs - self.available - self.delivering
end

--- Item Class
Item = {}
Item.__index = Item
function Item:create(o)
    local item = {}
    if o == nil then
        o = {}
    end
    setmetatable(item, Item)
    item.tags = o.tags or {}
    item.name = o.name or ""
    item.maxStackSize = o.maxStackSize or 64
    item.fingerprint = o.fingerprint or nil
    item.count = o.count or 0
    item.components = o.components or {}
    item.displayName = o.displayName or {}
    return item
end

--- Utility Functions

local function orderTableValAlphabetically(tableToOrder)
    table.sort(tableToOrder)
end

local function findCenter(w, h)
    local centerX = math.floor(w / 2)
    local centerY = math.floor(h / 2)
    return centerX, centerY
end

-- Find display size of string
local function findStringSize(str)
    local length = 0
    for _ in string.gmatch(str, ".") do
        length = length + 1
    end
    return length
end

local function clickWithinArea (clickX, clickY, areaX, areaY, areaW, areaH)
    return clickX ~= -1 and clickY ~= -1
        and clickX >= areaX and clickX < areaX + areaW
        and clickY >= areaY and clickY < areaY + areaH
end

local function clearMon(monitor)
    if monitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColour(colors.white)
    end
end

local function initializeMonitor(monitor)
    if monitor then
        monitor.setTextScale(0.5)
        mon_size_x, mon_size_y = monitor.getSize()
        clearMon(monitor)
        VisualData.display_monitor = window.create(monitor, 1, 1, mon_size_x - VisualData.page_button_size_x, mon_size_y)
    end
end

local function registerPageSwap()
    VisualData.pageSwapRequested = true
end

local function swapPageForward()
    if VisualData.pageFunctionList ~= nil and #VisualData.pageFunctionList >= 2 then
        if VisualData.pageNumber < #VisualData.pageFunctionList then
            VisualData.pageNumber = VisualData.pageNumber + 1
        else
            VisualData.pageNumber = 1
        end
        VisualData.pageFunction = VisualData.pageFunctionList[VisualData.pageNumber]
    end
    registerPageSwap()
end

local function swapPageBackward()
    if VisualData.pageFunctionList ~= nil and #VisualData.pageFunctionList >= 2 then
        if VisualData.pageNumber > 1 then
            VisualData.pageNumber = VisualData.pageNumber - 1
        else
            VisualData.pageNumber = #VisualData.pageFunctionList
        end
        VisualData.pageFunction = VisualData.pageFunctionList[VisualData.pageNumber]
    end
    registerPageSwap()
end

-- Event Listeners
local function listenKeyPressEvent()
    VisualData.key_event = {key_press = -1, is_held = false}
    local _, key, held = os.pullEvent("key")
    VisualData.key_event = {key_press = key, is_held = held}
    -- if key then
    --     print("Key Pressed: " .. keys.getName(key) .. " | Held: " .. tostring(held))
    -- end
end

local function listenTouchEvent()
    VisualData.x_touch, VisualData.y_touch = -1, -1
    if mon then
        local _, _, x_event, y_event = os.pullEvent("monitor_touch")
        VisualData.x_touch, VisualData.y_touch = x_event, y_event
    else
        sleep(VisualData.redrawSpeed)
    end
end

local function listenResizeEvent()
    local _, mon_resize_event = os.pullEvent("monitor_resize")
    local monitor_event = peripheral.wrap(mon_resize_event)
    initializeMonitor(monitor_event)
end

--- MineColonies Functions

-- Get list of work order IDs
local function getWorkOrdersIds(colonyIntegrator)
    local orders = colonyIntegrator.getWorkOrders()
    local result = {}
    for k in ipairs(orders) do
        table.insert(result, orders[k].id)
    end
    return result
end

-- Get all resources from all work orders
local function getAllResourcesFromOrders(colonyIntegrator)
    local orders = getWorkOrdersIds(colonyIntegrator)
    local resources = {}
    for _, orderId in ipairs(orders) do
        local orderResources = colonyIntegrator.getWorkOrderResources(orderId)
        for index in ipairs(orderResources or {}) do
            table.insert(resources, orderResources[index])
        end
    end
    return resources
end

--- Builds the list of missing items from work orders
local function getRequestedItems(colonyIntegrator)
    if colonyIntegrator then
        local resources = getAllResourcesFromOrders(colonyIntegrator)
        local resourcesNeeded = {}
        if resources ~= nil and #resources > 0 then
            for _, res in ipairs(resources) do
                if res.status ~= "NOT_NEEDED" then
                    table.insert(resourcesNeeded, res)
                end
            end
        end
        return resourcesNeeded
    end
end

local function sendChatMessageToPlayer(message)
    if message and chatbox then
        chatbox.sendMessageToPlayer(message, "hugopaq2", "ALERT")
    end
end

--- Storage Functions

-- Find Storage Peripheral
local function findStorage()
    local storageTypeList = { "minecraft:barrel", "sophisticatedstorage:barrel", "minecraft:chest"}
    for _, storageType in ipairs(storageTypeList) do
        local foundStorage = peripheral.find(storageType)
        if foundStorage then
            storage = foundStorage
            break
        end
    end
end

-- Check if storage contains at least one of the specified item
local function checkIfStorageContainsItemAny(item)
    if storage then
        local items = storage.list()
        for _, itemStorage in pairs(items) do
            if itemStorage.name == item.name then
                return true
            end
        end
    end
    return false
end

-- Check total quantity of specified item in storage
local function checkStorageItemQty(storagePeripheral, item)
    if storagePeripheral then
        local items = storagePeripheral.list()
        local itemCount = 0
        for _, itemStorage in pairs(items) do
            if itemStorage.name == item.name then
                itemCount = itemCount + itemStorage.count
            end
        end
        return itemCount
    end
    return 0
end

-- Check maximum item count storage can hold
local function checkStorageMaxItemCount()
    if storage then
        local storageSize = storage.size()
        local storageMaxInSlot = storage.getItemLimit(1)
        return storageSize * storageMaxInSlot
    end
    return 0
end

-- Check if there is space in storage
local function checkIfSpaceInStorage(storagePeriph)
    if storagePeriph then
        local items = storagePeriph.list()
        local itemCount = 0
        for _ in pairs(items) do
            itemCount = itemCount + 1
        end
        local maxSlots = storagePeriph.size()
        return itemCount < maxSlots
    end
    return false
end

local function checkPlayerInventoryItemQty(inventoryManagerPeripheral, item)
    if inventoryManagerPeripheral and item then
        local items = inventoryManagerPeripheral.getItems()
        local itemCount = 0
        for _, invItem in pairs(items) do
            if invItem.name == item.name then
                itemCount = itemCount + invItem.count
            end
        end
        return itemCount
    end
    return 0
end

--- ME System Functions

local function checkItemQtyInMeSystem(meSystemPeripheral, item)
    if meSystemPeripheral and item then
        local itemInMe = meSystemPeripheral.getItem({name = item.name})
        if itemInMe then
            return itemInMe.count
        end
    end
    return 0
end

local function getPatternForItem(meSystemPeripheral, item)
    if meSystemPeripheral and item and meSystemPeripheral.isCraftable({name = item.name}) then
        local patterns = meSystemPeripheral.getPatterns()
        for _, pattern in pairs(patterns) do
            for _, output in pairs(pattern.outputs) do
                if output.name == item.name then
                    return pattern
                end
            end
        end
    end
    return nil
end

--- Check if item can be crafted in ME System given current resources, amount needed, and crafting patterns. This will also check if inputs can be crafted recursively.
--- Returns table with canCraft boolean and missingInputs list with the item and amount needed
--- If canCraft is true, missingInputs will be empty
--- If canCraft is false, missingInputs will contain the items and amounts needed to craft the requested item
--- Example return:
--- { 
---     canCraft = false,
---     missingInputs = {
---         { name = "minecraft:iron_ingot", amount = 10 },
---         { name = "minecraft:stick", amount = 5 }
---     }
--- }
local function canCraftItemRecursive(meSystemPeripheral, item, amount)
    local result = {
        canCraft = false,
        missingInputs = {}
    }
    if not (meSystemPeripheral and item and amount) then
        return result
    end

    local pattern = getPatternForItem(meSystemPeripheral, item)
    if not pattern then
        -- If no pattern, can't craft, add the item itself as missing
        table.insert(result.missingInputs, { name = item.name, amount = amount })
        return result
    end

    local allInputsAvailable = true

    for _, entry in pairs(pattern.inputs) do
        local input = entry.primaryInput
        local requiredQty = input.count * amount * entry.multiplier
        local availableQty = checkItemQtyInMeSystem(meSystemPeripheral, input)
        if availableQty < requiredQty then
            local missingAmount = requiredQty - availableQty
            -- Recursively check if the missing input can be crafted
            local subResult = canCraftItemRecursive(meSystemPeripheral, input, missingAmount)
            if not subResult.canCraft then
                -- Add all missing inputs from the recursive call (flat list)
                for _, missing in ipairs(subResult.missingInputs) do
                    table.insert(result.missingInputs, missing)
                end
                allInputsAvailable = false
            end
        end
    end

    if allInputsAvailable and #result.missingInputs == 0 then
        result.canCraft = true
    end

    return result
end

local function craftRequestedItem(meSystemPeripheral, item, amount)
    local craftingResult = {
        job = nil,
        canCraft = false,
        missingInputs = {}
    }
    if meSystemPeripheral and item and amount > 0 and meSystemPeripheral.isCraftable({name = item.name}) then
        print("Attempting to craft item: " .. item.name .. " | Amount: " .. amount)
        -- Look for the crafting pattern
        local canCraftRec = canCraftItemRecursive(meSystemPeripheral, item, amount)
        if not canCraftRec.canCraft then
            --- If cannot craft, return missing inputs
            craftingResult.missingInputs = canCraftRec.missingInputs
        else
            --- If can craft, initiate crafting job
            craftingResult.job = meSystemPeripheral.craftItem({name = item.name, count = amount})
            craftingResult.canCraft = true
        end
    end
    return craftingResult
end

--- Compare two missing inputs lists for equality
local function isMissingInputsEqual(missingInputsA, missingInputsB)
    if #missingInputsA ~= #missingInputsB then
        return false
    end
    for i, inputA in ipairs(missingInputsA) do
        local foundMatch = false
        for j, inputB in ipairs(missingInputsB) do
            if inputA.name == inputB.name and inputA.amount == inputB.amount then
                foundMatch = true
                break
            end
        end
        if not foundMatch then
            return false
        end
    end
    return true
end

--- Compare two crafts missing inputs lists for equality
local function isCraftsMissingInputsEqual(craftsA, craftsB)
    if #craftsA ~= #craftsB then
        return false
    end
    for i, craftA in ipairs(craftsA) do
        local foundMatch = false
        for j, craftB in ipairs(craftsB) do
            if craftA.item.name == craftB.item.name and craftA.amount == craftB.amount then
                if isMissingInputsEqual(craftA.missingInputs, craftB.missingInputs) then
                    foundMatch = true
                    break
                end
            end
        end
        if not foundMatch then
            return false
        end
    end
    return true
end

-- UI Elements

local header, drawRectangle, button, writeToMonitor, drawLine, scrollableDisplay, writeToMonitorWithPadding, scrollableDisplayFromList

writeToMonitor = function(monitor, text, x_tab, y_line, backgroundColor, textColor)
    if monitor then
        local initialX, initialY = monitor.getCursorPos()
        local originalColor = monitor.getTextColour()
        local originalBackground = monitor.getBackgroundColor()
        if textColor then
            monitor.setTextColor(textColor)
        end
        if backgroundColor then
            monitor.setBackgroundColor(backgroundColor)
        end
        monitor.setCursorPos(x_tab or initialX, y_line or initialY)
        monitor.write(text)
        monitor.setCursorPos(initialX, initialY)
        monitor.setTextColor(originalColor)
        monitor.setBackgroundColor(originalBackground)
    end
end

writeToMonitorWithPadding = function(monitor, text, x_tab, y_line, box_width, box_height, backgroundColor, textColor, padl, padu, padr, padd)
    if monitor then
        if padl and (padu == nil and padr == nil and padd == nil) then
            padu, padr, padd = padl, padl, padl
        elseif padl and padu and (padr == nil and padd == nil) then
            padr, padd = padl, padu
        end
        local size_x = box_width + (padl or 0) + (padr or 0)
        local size_y = box_height + (padu or 0) + (padd or 0)
        local paddedWindow = window.create(monitor, x_tab, y_line, size_x, size_y)
        paddedWindow.setBackgroundColor(backgroundColor or colors.black)
        paddedWindow.clear()
        local textPosX = (padl or 0)
        local textPosY = (padu or 0)
        if padl then
            textPosX = textPosX + 1
            textPosY = textPosY + 2
        end
        writeToMonitor(monitor, text or "", x_tab + textPosX, y_line + textPosY, backgroundColor, textColor)
    end
end

drawLine = function(monitor, x, y, w, h, color)
    if monitor then
        local line_window = window.create(monitor, x, y, w, h)
        line_window.setBackgroundColor(color or colors.black)
        line_window.clear()
    end
end

drawRectangle = function(monitor, x, y, w, h, lineWidht, color)
    if monitor then
        -- Draw top line
        drawLine(monitor, x, y, w, lineWidht, color)
        -- Draw bottom line
        drawLine(monitor, x, y + h - lineWidht, w, lineWidht, color)
        -- Draw left line
        drawLine(monitor, x, y + lineWidht, lineWidht, h - lineWidht, color)
        -- -- Draw right line
        drawLine(monitor, x + w - lineWidht, y + lineWidht, lineWidht, h - lineWidht, color)
    end
end

header = function(monitor, w, h, color, label)
    if monitor then
        local header_window = window.create(monitor, 1, 1, w, h)
        header_window.setBackgroundColor(color or colors.black)
        header_window.setTextColour(colors.white)
        header_window.clear()
        local centerX, centerY = findCenter(w, h)
        centerX = centerX + 1 - math.floor(findStringSize(label) / 2)
        writeToMonitor(header_window, label, centerY, centerX)
    end
end

button = function(monitor, x, y, w, h, color, label, flashColor)
    local pressed = false
    if monitor then
        local button_window = window.create(monitor, x, y, w, h)
        button_window.setBackgroundColor(color or colors.black)
        button_window.clear()
        local centerX, centerY = findCenter(w, h)
        centerX = centerX + 1 - math.floor(findStringSize(label) / 2)
        -- Adjust for even height buttons
        if h > 1 then
            centerY = centerY + 1
        end
        writeToMonitor(button_window, label, centerX, centerY)
        if clickWithinArea(VisualData.x_touch, VisualData.y_touch, x, y, w, h) then
            local click_window = window.create(monitor, x, y, w, h)
            click_window.setBackgroundColor(flashColor or colors.white)
            click_window.clear()
            pressed = true
        end
    end
    return pressed
end

scrollableDisplay = function(monitor, contentFunction, scrollPosition, ...)
    if monitor then
        local monSizeX, monSizeY = monitor.getSize()
        local displayWindowOffsetX, displayWindowOffsetY = 3, 3
        local rectX, rectY, rectSizeX, rectSizeY, rectLineWidth = 2, 2, monSizeX - displayWindowOffsetX, monSizeY - displayWindowOffsetY, 1
        local buttonSizeX, buttonSizeY = 3, 3
        local displayWindowX, displayWindowY, displayWindowSizeX, displayWindowSizeY = rectX + rectLineWidth + buttonSizeX, rectY + rectLineWidth, rectSizeX - rectLineWidth*2 - buttonSizeX, rectSizeY - rectLineWidth*2
        drawRectangle(monitor, rectX, rectY, rectSizeX, rectSizeY, rectLineWidth, colors.orange)
        if button(monitor, rectX + rectLineWidth, rectY + rectLineWidth, buttonSizeX, buttonSizeY, colors.green, "+") then
            scrollPosition = scrollPosition + 1
        end
        if button(monitor, rectX + rectLineWidth, rectY + rectLineWidth + buttonSizeY, buttonSizeX, buttonSizeY, colors.green, "-") then
            scrollPosition = scrollPosition - 1
        end
        local displayWindow = window.create(monitor, displayWindowX, displayWindowY, displayWindowSizeX, displayWindowSizeY)
        displayWindow.setBackgroundColor(colors.black)
        displayWindow.clear()
        contentFunction(displayWindow, scrollPosition, ...)
    end
    return scrollPosition
end

--- Scrollable Display from List
--- Creates a scrollable display on the given monitor using the provided content list.
--- Each item in the content list is written to the monitor starting from the specified scroll position.
--- @param monitor table
--- @param contentList table
scrollableDisplayFromList = function(monitor, contentList, scrollPosition)
    local contentFunction = function(displayWindow, scrollPos, contentListFunc)
        local line = scrollPos + 1
        for _, content in pairs(contentListFunc) do
            writeToMonitor(displayWindow, content, 3, line)
            line = line + 1
        end
    end
    return scrollableDisplay(monitor, contentFunction, scrollPosition, contentList)
end

----------------------------------------
----------------------------------------
--- SPACER------------------------------
----------------------------------------
----------------------------------------

-- Display Functions

-- Minecolonies Displays
local supplyPause = false
local CitizenDisplayScroll = 0
local function displayCitizensStats(monitor)
    if monitor and colony then
        clearMon(monitor)
        local monitor_size_x, monitor_size_y = monitor.getSize()
        local displayWindowOffsetX, displayWindowOffsetY = 3, 3
        local rectX, rectY, rectSizeX, rectSizeY, rectLineWidth = 2, 2, monitor_size_x - displayWindowOffsetX, monitor_size_y - displayWindowOffsetY, 1
        local buttonSizeX, buttonSizeY = 3, 3
        local displayWindowX, displayWindowY, displayWindowSizeX, displayWindowSizeY = rectX + rectLineWidth + buttonSizeX, rectY + rectLineWidth, rectSizeX - rectLineWidth*2 - buttonSizeX, rectSizeY - rectLineWidth*2
        drawRectangle(monitor, rectX, rectY, rectSizeX, rectSizeY, rectLineWidth, colors.orange)
        if button(monitor, rectX + rectLineWidth, rectY + rectLineWidth, buttonSizeX, buttonSizeY, colors.green, "+") then
            CitizenDisplayScroll = CitizenDisplayScroll + 1
        end
        if button(monitor, rectX + rectLineWidth, rectSizeY - rectLineWidth - 1, buttonSizeX, buttonSizeY, colors.green, "-") then
            CitizenDisplayScroll = CitizenDisplayScroll - 1
        end
        local displayWindow = window.create(monitor, displayWindowX, displayWindowY, displayWindowSizeX, displayWindowSizeY)
        displayWindow.setBackgroundColor(colors.purple)
        displayWindow.clear()

        -- Fetch and display citizen stats
        local citizens = colony.getCitizens()
        local line, tab = CitizenDisplayScroll + 1, 3
        for _, value in pairs(citizens) do
            writeToMonitor(displayWindow, "Name: " .. value.name .. " | Saturation: " .. value.saturation, tab, line)
            line = line + 1
        end
    end
end

--- Display Work Order Resources on Monitor using scrollableDisplayFromList
local function displayWorkOrderResources(monitor)
    if monitor and colony then
        local resourcesNeeded = getRequestedItems(colony)
        local contentList = {}
        for _, resource in ipairs(resourcesNeeded) do
            local text = resource.displayName .. " | Nd:" .. resource.needs .. " | Avail:" .. resource.available .. " | Deliv:" .. resource.delivering .. " | Sts:" .. resource.status
            table.insert(contentList, text)
        end
        VisualData.scroll = scrollableDisplayFromList(monitor, contentList, VisualData.scroll)
    end
end


local function displaySearchPeripherals(monitor)
    local allPeripherals = peripheral.getNames()
    if monitor then
        local line = 2
        for _, peripheralName in ipairs(allPeripherals) do
            local peripheralType = peripheral.getType(peripheralName)
            local text = "Peripheral: " .. peripheralName .. " | Type: " .. peripheralType
            writeToMonitor(monitor, text, 1, line)
            line = line + 1
        end
    else
        print("Peripherals connected:")
        for _, peripheralName in ipairs(allPeripherals) do
            local peripheralType = peripheral.getType(peripheralName)
            print( "Peripheral: " .. peripheralName .. " | Type: " .. peripheralType )
        end
    end
end

-- Minecolonies Supply Script : Supply requested items from work orders to storage peripheral
local function supplyMinecoloniesScript()
    if not colony then
        print("Missing colony integrator peripheral.")
        return
    end
    if not meSystem then
        print("Missing ME Bridge peripheral.")
        return
    end
    if not storage then
        print("Missing Storage peripheral.")
        return
    end
    local requestedItems = getRequestedItems(colony)
    local craftsMissingInputs = {}
    if checkIfSpaceInStorage(storage) then
        for _, valueResource in pairs(requestedItems) do
            local resource = Resource:create(valueResource)
            if resource then
                local item = Item:create(resource.item)
                local itemInMe = Item:create(meSystem.getItem({name = item.name}))
                local itemInStorageQty = checkStorageItemQty(storage, item)
                local itemInPlayerInvQty = checkPlayerInventoryItemQty(inventoryManager, item)
                local amountNeeded = resource:neededAmount()
                --- Only proceed if there is a need for the item
                if itemInStorageQty < amountNeeded and itemInPlayerInvQty < amountNeeded then
                    --- Calculate amount to transfer from ME System to Storage minus what is already in storage and player inventory
                    local amountToTransfer = amountNeeded - itemInStorageQty - itemInPlayerInvQty
                    if MeSystemInfo.crafting.job == nil and itemInMe.count < amountNeeded then
                        --- Calculate amount to craft minus what is already in ME System, storage, and player inventory
                        local craftAmount = amountNeeded - itemInMe.count - itemInStorageQty - itemInPlayerInvQty
                        local craftReqResult = craftRequestedItem(meSystem, {name = item.name}, craftAmount)
                        MeSystemInfo.crafting.job = craftReqResult.job
                        if not craftReqResult.canCraft then
                            table.insert(craftsMissingInputs, { item = item, amount = craftAmount, missingInputs = craftReqResult.missingInputs })
                        end
                    else
                        meSystem.exportItem({name = item.name, count = amountToTransfer}, "left")
                    end
                end
            end
        end
    else
        print("Storage is full.")
    end
    return craftsMissingInputs
end

local function minecoloniesScript()
    if tick % 40 == 0 then
        if not supplyPause then
            local craftsMissingInputs = supplyMinecoloniesScript()
            if not isCraftsMissingInputsEqual(craftsMissingInputs, MeSystemInfo.crafting.craftsMissingInputs) or MeSystemInfo.crafting.job ~= nil then
                if  MeSystemInfo.crafting.job and MeSystemInfo.crafting.job.isDone() then
                    MeSystemInfo.crafting.job = nil
                end
                MeSystemInfo.crafting.craftsMissingInputs = craftsMissingInputs
                clearMon(VisualData.display_monitor)
            end
        else
            print("Supply paused.")
        end

    end
end

--- @param monitor table
--- @return nil
--- Displays the results of the supplying script on the provided monitor.
--- Will show the crafting job ID and any missing inputs for crafting requests.
--- The missing inputs are displayed in a nested format, showing the item name and amount needed with white text and red background.
local function displaySupplyingResults(monitor)
    if monitor then
        local buttonText = "Pause"
        if supplyPause then
            buttonText = "Resume"
        end
        if button(monitor, 1, 1, 5, 1, colors.blue, buttonText) then
            supplyPause = not supplyPause
        end
        local line = 2
        writeToMonitor(monitor, "Supplying Results:", 1, line, colors.green, colors.white)
        line = line + 2
        if MeSystemInfo.crafting.job then
            writeToMonitor(monitor, "Current Crafting Job ID: " .. tostring(MeSystemInfo.crafting.job), 1, line, colors.black, colors.green)
            line = line + 2
        else
            writeToMonitor(monitor, "No active crafting job.", 1, line, colors.black, colors.gray)
            line = line + 2
        end
        if #MeSystemInfo.crafting.craftsMissingInputs > 0 then
            writeToMonitor(monitor, "Missing Inputs for Crafting Requests:", 1, line, colors.black, colors.white)
            line = line + 2
            for _, craftInfo in pairs(MeSystemInfo.crafting.craftsMissingInputs) do
                writeToMonitor(monitor, "Item: " .. craftInfo.item.displayName .. " | Amount: " .. craftInfo.amount, 1, line, colors.orange, colors.white)
                line = line + 1
                for _, missingInput in pairs(craftInfo.missingInputs) do
                    writeToMonitor(monitor, "   - Missing: " .. missingInput.name .. " | Amount: " .. missingInput.amount, 1, line, colors.red, colors.white)
                    line = line + 1
                end
                line = line + 1
            end
        else
            writeToMonitor(monitor, "All crafting requests have sufficient inputs.", 1, line, colors.black, colors.white)
        end
    end
end

local function displayScrollablePeripheralsFunctionsList(monitor)
    local function contentFunction(displayWindow, scrollPosition)
        local line = 1 + scrollPosition
        local functionList = {}
        for key, _ in pairs(meSystem) do
            table.insert(functionList, key)
        end
        orderTableValAlphabetically(functionList)
        for _, val in pairs(functionList) do
            writeToMonitor(displayWindow, val, 1, line)
            line = line + 1
        end
    end
    VisualData.scroll = scrollableDisplay(monitor, contentFunction, VisualData.scroll)
end

local function displayPage(monitor, pageFunction)
    if monitor then
        pageFunction(monitor)
    end
end

local function displayPagesButton(monitor)
    if monitor then
        local button_size_x, button_size_y = VisualData.page_button_size_x, 5
        local monSizeX, monSizeY = monitor.getSize()
        if button(monitor, monSizeX - button_size_x + 1, 1, button_size_x, button_size_y, colors.blue, " + ") then
            swapPageForward()
        end
        if button(monitor, monSizeX - button_size_x + 1, monSizeY - button_size_y + 1, button_size_x, button_size_y, colors.blue, " - ") then
            swapPageBackward()
        end
        local pageTextInfo = VisualData.pageNumber .. "/" .. #VisualData.pageFunctionList
        local pos_y, pos_x = math.floor((monSizeY) / 2) - math.floor(button_size_y / 2), monSizeX - button_size_x + 1
        writeToMonitorWithPadding(monitor, pageTextInfo, pos_x, pos_y, button_size_x, button_size_y, colors.blue, colors.white, 1)
        if VisualData.pageSwapRequested then
            clearMon(VisualData.display_monitor)
        end
    end
end

local function mainAsync()
    displayPagesButton(mon)
    displayPage(VisualData.display_monitor, VisualData.pageFunction)

    -- Always run supply after display to properly catch touch events and key presses
    minecoloniesScript()

    -- Yeild to allow event listeners to run
    sleep(VisualData.redrawSpeed)
end

local function main()
    if mon == nil then
        print("No monitor detected. Please attach a monitor.")
        return
    end

    -- Find Storage Peripheral
    findStorage()

    -- Initialize Monitor
    initializeMonitor(mon)

    -- Initialize Pages
    VisualData.pageFunctionList = {displaySupplyingResults, displaySearchPeripherals, displayWorkOrderResources}
    VisualData.pageFunction = VisualData.pageFunctionList[1]

    -- Main Loop
    while mon ~= nil do
        -- Handle Page Swaps
        if VisualData.pageSwapRequested then
            clearMon(VisualData.display_monitor)
            VisualData.pageSwapRequested = false
        end

        -- Display Monitor and Listen for Events
        parallel.waitForAny(mainAsync, listenTouchEvent, listenKeyPressEvent, listenResizeEvent)
        tick = tick + 1
    end
end

main()