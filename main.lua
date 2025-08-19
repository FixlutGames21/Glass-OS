-- main.lua
-- Головний файл, який запускає Glass OS (клон Windows 2000)

local component = require("component")
local event = require("event")
local os = require("os")
local computer = require("computer") -- Переконайтесь, що computer завантажено

-- Завантажуємо наші бібліотеки
local colors = require("lib.colors")
local drawing = require("lib.drawing")
local utils = require("lib.utils")
local Window = require("gui_elements.window")

-- --- Ініціалізація GPU та екрана ---
local gpu = component.gpu
if not gpu then
    print("Помилка: GPU не знайдено. Переконайтеся, що відеокарта встановлена.")
    os.exit()
end
local screenAddress = component.list("screen")()
if not screenAddress then
    print("Помилка: Екран не знайдено. Переконайтеся, що екран підключений.")
    os.exit()
end

local maxWidth, maxHeight = gpu.maxResolution()
gpu.setResolution(maxWidth, maxHeight)
print("Роздільна здатність встановлена:", maxWidth, "x", maxHeight)

drawing.init(maxWidth, maxHeight)

--------------------------------------------------------------------------------
-- Параметри елементів інтерфейсу
--------------------------------------------------------------------------------
local taskbarConfig = {
    x = 1,
    y = maxHeight,
    width = maxWidth,
    height = 1
}

local startButtonConfig = {
    x = 1,
    y = maxHeight,
    width = 7,
    height = 1,
    text = "Пуск"
}

local startMenuConfig = {
    x = 1,
    y = maxHeight - 8,
    width = 20,
    height = 8,
    isVisible = false,
    items = {
        {text = "Мій комп'ютер", action = "my_computer"},
        {text = "Термінал", action = "terminal"},
        {text = "Налаштування", action = "settings"},
        {text = "---", action = nil},
        {text = "Вимкнути", action = "shutdown"}
    }
}

--------------------------------------------------------------------------------
-- Менеджер вікон та програм (спрощено)
--------------------------------------------------------------------------------
local activeWindows = {}
local zOrder = {}

local function runApp(appName)
    print("Запит на запуск програми: " .. tostring(appName))
    if appName == "shutdown" then
        return true
    elseif appName == "terminal" then
        print("Запускаємо Термінал (поки що заглушка).")
    else
        print("Програма '" .. tostring(appName) .. "' ще не реалізована.")
    end
    return false
end

--------------------------------------------------------------------------------
-- Функції для малювання основних компонентів GUI
--------------------------------------------------------------------------------
local function drawDesktop()
    drawing.clearScreen()
end

local function drawTaskbar()
    gpu.setBackground(colors.TASKBAR_GREY)
    gpu.fill(taskbarConfig.x, taskbarConfig.y, taskbarConfig.width, taskbarConfig.height, " ")

    drawing.draw3dButton(startButtonConfig.x, startButtonConfig.y,
                         startButtonConfig.width, startButtonConfig.height,
                         startButtonConfig.text, startMenuConfig.isVisible)
    
    local time_str = os.date("%H:%M:%S")
    gpu.setForeground(colors.BLACK)
    gpu.setBackground(colors.TASKBAR_GREY)
    gpu.set(taskbarConfig.width - #time_str - 1, taskbarConfig.y, time_str)
end

local function drawStartMenu()
    if not startMenuConfig.isVisible then return end

    local sm = startMenuConfig
    gpu.setBackground(colors.MENU_BG)
    gpu.setForeground(colors.BLACK)
    gpu.fill(sm.x, sm.y, sm.width, sm.height, " ")

    gpu.setBackground(colors.WINDOW_BORDER)
    gpu.set(sm.x, sm.y, " ")
    gpu.set(sm.x + sm.width - 1, sm.y, " ")
    gpu.set(sm.x, sm.y + sm.height - 1, " ")
    gpu.set(sm.x + sm.width - 1, sm.y + sm.height - 1, " ")
    gpu.fill(sm.x + 1, sm.y, sm.width - 2, 1, " ")
    gpu.fill(sm.x + 1, sm.y + sm.height - 1, sm.width - 2, 1, " ")
    gpu.fill(sm.x, sm.y + 1, 1, sm.height - 2, " ")
    gpu.fill(sm.x + sm.width - 1, sm.y + 1, 1, sm.height - 2, " ")

    for i, item in ipairs(sm.items) do
        local itemY = sm.y + i -1
        if item.text == "---" then
            gpu.setBackground(colors.BUTTON_3D_DARK)
            gpu.set(sm.x + 2, itemY, string.rep("─", sm.width - 4))
            gpu.setBackground(colors.BUTTON_3D_LIGHT)
            gpu.set(sm.x + 2, itemY + 1, string.rep("─", sm.width - 4))
            gpu.setBackground(colors.MENU_BG)
        else
            gpu.setForeground(colors.BLACK)
            gpu.setBackground(colors.MENU_BG)
            gpu.set(sm.x + 2, itemY, item.text)
        end
    end
end

-- Головна функція перемалювання всього інтерфейсу
local function redrawGUI()
    drawDesktop()

    for i, win in ipairs(activeWindows) do
        win:draw()
    end

    drawTaskbar()
    drawStartMenu()
end

--------------------------------------------------------------------------------
-- Основний цикл ОС 🖥️
--------------------------------------------------------------------------------

local testWindow = Window.new(10, 5, 40, 15, "Моє перше вікно Glass OS")
table.insert(activeWindows, testWindow)
testWindow.isActive = true

redrawGUI() -- Первинне малювання після завантаження ОС

local running = true
-- !!! Видалено автоматичний таймер оновлення екрана !!!
-- Оновлення тепер відбувається лише за подіями миші/клавіатури

while running do
    local _, _, name, p1, p2, p3, p4 = event.pull()

    if name == "mouse_click" then
        local mouseX, mouseY = p2, p3
        local button = p4
        local clickHandledByGUI = false

        -- Перевіряємо вікна
        for i = #activeWindows, 1, -1 do -- Проходимо у зворотньому порядку, щоб спочатку обробляти верхні вікна
            local win = activeWindows[i]
            if win.isVisible then
                if utils.isClicked(mouseX, mouseY, win.x, win.y, win.width, win.height) then
                    -- Зробити це вікно активним
                    for _, otherWin in ipairs(activeWindows) do
                        otherWin.isActive = false
                    end
                    win.isActive = true
                    -- І перевіряємо, чи вікно обробило клік (наприклад, по кнопці закриття)
                    if win:handleMouseClick(mouseX, mouseY, button) then
                        clickHandledByGUI = true
                        break
                    end
                end
            end
        end

        -- Якщо клік не оброблено вікном, перевіряємо меню "Пуск"
        if not clickHandledByGUI then
            if startMenuConfig.isVisible then
                if utils.isClicked(mouseX, mouseY, startMenuConfig.x, startMenuConfig.y, startMenuConfig.width, startMenuConfig.height) then
                    local relativeY = mouseY - startMenuConfig.y
                    local itemIndex = relativeY + 1
                    local selectedItem = startMenuConfig.items[itemIndex]
                    
                    if selectedItem and selectedItem.text ~= "---" then
                        -- Ефект виділення при натисканні
                        gpu.setBackground(colors.HIGHLIGHT)
                        gpu.setForeground(colors.WHITE)
                        gpu.fill(startMenuConfig.x + 1, startMenuConfig.y + itemIndex -1, startMenuConfig.width - 2, 1, " ")
                        gpu.set(startMenuConfig.x + 2, startMenuConfig.y + itemIndex -1, selectedItem.text)
                        os.sleep(0.1) -- Коротка пауза для візуального ефекту

                        local shouldShutdown = runApp(selectedItem.action)
                        if shouldShutdown then
                            running = false
                        end
                    end
                    startMenuConfig.isVisible = false
                    clickHandledByGUI = true
                else
                    -- Клік поза меню "Пуск" закриває його
                    startMenuConfig.isVisible = false
                    clickHandledByGUI = true
                end
            end
        end

        -- Обробка кнопки "Пуск" (якщо клік не оброблено раніше)
        if not clickHandledByGUI and utils.isClicked(mouseX, mouseY, startButtonConfig.x, startButtonConfig.y, startButtonConfig.width, startButtonConfig.height) then
            startMenuConfig.isVisible = not startMenuConfig.isVisible
            clickHandledByGUI = true
        end
        
        -- Перемальовуємо GUI після обробки кліку
        redrawGUI()

    elseif name == "mouse_drag" then
        local mouseX, mouseY = p2, p3
        local dragHandledByGUI = false
        for i = #activeWindows, 1, -1 do
            local win = activeWindows[i]
            if win.isDragging then
                if win:handleMouseMove(mouseX, mouseY) then
                    dragHandledByGUI = true
                    break
                end
            end
        end
        if dragHandledByGUI then
            redrawGUI() -- Перемальовуємо під час перетягування вікна
        end

    elseif name == "mouse_up" then
        local mouseX, mouseY = p2, p3
        local button = p4
        local clickHandledByGUI = false -- Назва змінної не зовсім коректна для mouse_up, але залишимо для послідовності
        for i = #activeWindows, 1, -1 do
            local win = activeWindows[i]
            if win:handleMouseUp(mouseX, mouseY, button) then
                clickHandledByGUI = true -- Означає, що подія "mouse_up" була оброблена вікном (наприклад, завершення перетягування)
                break
            end
        end
        -- Очистити список вікон від тих, що були закриті
        local newActiveWindows = {}
        for _, win in ipairs(activeWindows) do
            if win.isVisible then
                table.insert(newActiveWindows, win)
            end
        end
        activeWindows = newActiveWindows
        redrawGUI() -- Перемальовуємо після відпускання миші (особливо після перетягування)

    elseif name == "key_down" then
        local char_code = p2
        local char = string.char(char_code)
        if char == "q" or char == "Q" then -- Для швидкого виходу
            running = false
        end
        -- TODO: Передавати події клавіатури активному вікну, якщо є
        redrawGUI() -- Перемальовуємо після натискання клавіші, якщо це може вплинути на інтерфейс
    end
end

--------------------------------------------------------------------------------
-- Завершення роботи ОС ---
--------------------------------------------------------------------------------
drawing.clearScreen()
gpu.setForeground(colors.WHITE)
gpu.set(1, 1, "До побачення! Glass OS вимикається.")
os.sleep(1.5)
gpu.fill(1, 1, maxWidth, maxHeight, " ")