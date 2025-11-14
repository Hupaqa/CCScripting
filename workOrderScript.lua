-- Testing Script

local colony = peripheral.find("colony_integrator")
local mon = peripheral.find("monitor")
local chatbox = peripheral.find("chat_box")
local meSystem = peripheral.find("me_bridge")
local mon_size_x, mon_size_y
local tick = 0
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
    scroll = 0,
    resources = {},
    workOrders = {},
    pageFunction = nil,
    pageFunctionList = nil,
    pageNumber = 1,
    pageSwapRequested = false,
    redrawSpeed = 0.1
}

--- Utility Functions

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

local function reverse(tab)
    for i = 1, #tab/2, 1 do
        tab[i], tab[#tab-i+1] = tab[#tab-i+1], tab[i]
    end
    return tab
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

function initializeMonitor(monitor)
    if monitor then
        monitor.setTextScale(0.5)
        mon_size_x, mon_size_y = monitor.getSize()
        clearMon(monitor)
        VisualData.display_monitor = window.create(monitor, 1, 1, mon_size_x - VisualData.page_button_size_x, mon_size_y)
        print("Display Monitor initialized. Size: " .. mon_size_x .. "x" .. mon_size_y)
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
    if key then
        print("Key Pressed: " .. keys.getName(key) .. " | Held: " .. tostring(held))
    end
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

-- Get list of work order IDs
local function getWorkOrdersIds()
    local orders = colony.getWorkOrders()
    local result = {}
    for k in ipairs(orders) do
        table.insert(result, orders[k].id)
    end
    return result
end

-- Get all resources from all work orders
local function getAllResourcesFromOrders()
    local orders = getWorkOrdersIds()
    local resources = {}
    for _, orderId in ipairs(orders) do
        local orderResources = colony.getWorkOrderResources(orderId)
        for index in ipairs(orderResources or {}) do
            table.insert(resources, orderResources[index])
        end
    end
    return resources
end

local function sendChatMessageToPlayer(message)
    if message and chatbox then
        chatbox.sendMessageToPlayer(message, "hugopaq2", "ALERT")
    end
end

-- UI Elements

local header, drawRectangle, button, writeToMonitor, drawLine, scrollableDisplay, writeToMonitorWithPadding

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

scrollableDisplay = function(monitor, contentFunction, scrollPosition)
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
        displayWindow.setBackgroundColor(colors.purple)
        displayWindow.clear()
        contentFunction(displayWindow, scrollPosition)
    end
    return scrollPosition
end

-- Display Functions

-- Minecolonies Displays
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

local function notifyItemsMissing(monitor)
    if monitor and colony then
        local resources = getAllResourcesFromOrders()
        local resourcesNeeded = {}
        local allFulfilled = true
        local firstItem = true
        if resources ~= nil and #resources > 0 then            
            for _, res in ipairs(resources) do
                if res.status ~= "NOT_NEEDED" then
                    local message = "Needed " .. res.displayName .. " -- Amount: " .. (res.needs - res.available)
                    table.insert(resourcesNeeded, res)
                    writeToMonitor(monitor, message, 4, 1, colors.red, colors.white)
                    button(monitor, 1, 1, 3, 1, colors.green, "+", colors.white)
                    if firstItem and tick % 60 == 0 then
                        sendChatMessageToPlayer(message)
                        firstItem = false
                    end
                    allFulfilled = false
                end
            end
            VisualData.resources = resourcesNeeded
        end
        if allFulfilled then
            clearMon(monitor)
            VisualData.resources = {}
            writeToMonitor(monitor, "No items needed!", 1, 1, colors.green, colors.white)
        end
    end
end

local function searchPeripherals(monitor)
    local allPeripherals = peripheral.getNames()
    if monitor then
        local line = 2
        for _, peripheralName in ipairs(allPeripherals) do
            local text = "Peripheral: " .. peripheralName .. " | Type: " .. peripheral.getType(peripheralName)
            writeToMonitor(monitor, text, 1, line)
            line = line + 1
        end
    end
end

local function displayInfoOfMeBridge(monitor)
    if monitor and meSystem then
        local items = meSystem.getItems()
        writeToMonitor(monitor, "ME Bridge Inventory Number:" .. #items, 1, 1, colors.yellow, colors.black)
        if VisualData.resources ~= nil and #VisualData.resources > 0 then
            local line = 2
            for _, neededResource in ipairs(VisualData.resources) do
                local itemMe = meSystem.getItem(neededResource.fingerprint)
                for key, value in pairs(itemMe or {}) do
                    print( "Key: " .. tostring(key) .. " | Value: " .. tostring(value) )
                end
                local availableInME = 0
                if itemMe then
                    availableInME = itemMe.quantity
                end
                local text = "Item: " .. neededResource.displayName .. " | Needed: " .. (neededResource.needs - neededResource.available) .. " | In ME: " .. availableInME
                writeToMonitor(monitor, text, 1, line)
                line = line + 1
            end
        end
    else
        writeToMonitor(monitor, "ME Bridge not found.", 1, 2)
    end
end

local function displayScrollablePeripheralsFunctionsList(monitor)
    local function contentFunction(displayWindow, scrollPosition)
        local line = 1 + scrollPosition
        for key,value in pairs(meSystem) do
            local text = "Function: " .. key .. " | Type: " .. type(value)
            writeToMonitor(displayWindow, text, 1, line)
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

local function displayAsync()
    displayPagesButton(mon)
    displayPage(VisualData.display_monitor, VisualData.pageFunction)
    sleep(VisualData.redrawSpeed)
end

local function main()
    if mon == nil then
        print("No monitor detected. Please attach a monitor.")
        return
    end

    -- Initialize Monitor
    initializeMonitor(mon)

    -- Initialize Pages
    VisualData.pageFunctionList = {notifyItemsMissing, displayCitizensStats, displayScrollablePeripheralsFunctionsList, displayInfoOfMeBridge}
    VisualData.pageFunction = VisualData.pageFunctionList[1]

    -- Main Loop
    while mon ~= nil do
        -- Handle Page Swaps
        if VisualData.pageSwapRequested then
            clearMon(VisualData.display_monitor)
            VisualData.pageSwapRequested = false
        end
        parallel.waitForAny(displayAsync, listenTouchEvent, listenKeyPressEvent, listenResizeEvent)
        tick = tick + 1
        -- print("Restarts loop..." .. "Redraw Speed: " .. string.format("%.1f", VisualData.redrawSpeed) .. "s")
    end
end

main()