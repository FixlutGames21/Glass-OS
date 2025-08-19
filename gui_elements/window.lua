-- gui_elements/window.lua
-- Клас для управління окремим вікном GUI

local component = require("component")
local gpu = component.gpu
local colors = require("lib.colors")
local utils = require("lib.utils")
local drawing = require("lib.drawing")

local Window = {}
Window.__index = Window

function Window.new(x, y, width, height, title)
    local self = setmetatable({}, Window)
    
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.title = title or "Вікно"
    self.isActive = false
    self.isVisible = true
    self.isDragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.isMinimized = false -- Нова властивість
    self.isMaximized = false -- Нова властивість

    self.content = {} -- Тут буде зберігатися вміст вікна
    
    return self
end

function Window:draw()
    if not self.isVisible or self.isMinimized then return end -- Не малюємо приховані або мінімізовані

    drawing.drawWindow(self.x, self.y, self.width, self.height, self.title, self.isActive)

    -- Малювання вмісту вікна (приклад, потім буде замінено)
    gpu.setBackground(colors.MENU_BG)
    gpu.setForeground(colors.BLACK)
    gpu.set(self.x + 2, self.y + 2, "Це вікно: " .. self.title)
    gpu.set(self.x + 2, self.y + 3, "X: " .. self.x .. " Y: " .. self.y)
    if self.isActive then
        gpu.set(self.x + 2, self.y + 4, "Активне вікно!")
    end
end

function Window:handleMouseClick(mx, my, button)
    local titlebarX = self.x + 1
    local titlebarY = self.y
    local titlebarWidth = self.width - 2
    local titlebarHeight = 1

    -- Кнопка Закрити (X)
    local closeBtnX = self.x + self.width - 4
    local closeBtnY = self.y
    if utils.isClicked(mx, my, closeBtnX, closeBtnY, 3, 1) then
        self:close()
        return true -- Клік оброблено
    end

    -- Кнопка Максимізувати (^)
    local maximizeBtnX = self.x + self.width - 7
    local maximizeBtnY = self.y
    if utils.isClicked(mx, my, maximizeBtnX, maximizeBtnY, 3, 1) then
        -- Логіка максимізації буде додана пізніше
        print("Натиснуто Максимізувати для: " .. self.title)
        return true
    end

    -- Кнопка Мінімізувати (_)
    local minimizeBtnX = self.x + self.width - 10
    local minimizeBtnY = self.y
    if utils.isClicked(mx, my, minimizeBtnX, minimizeBtnY, 3, 1) then
        -- Логіка мінімізації буде додана пізніше
        print("Натиснуто Мінімізувати для: " .. self.title)
        return true
    end

    -- Клік по заголовку (для перетягування та активації)
    if utils.isClicked(mx, my, titlebarX, titlebarY, titlebarWidth, titlebarHeight) then
        self.isDragging = true
        self.dragOffsetX = mx - self.x
        self.dragOffsetY = my - self.y
        return true -- Клік оброблено
    end

    return false -- Клік не оброблено цим вікном
end

function Window:handleMouseMove(mx, my)
    if self.isDragging then
        local newX = mx - self.dragOffsetX
        local newY = my - self.dragOffsetY

        -- Обмеження перетягування, щоб вікно не виходило за межі екрану
        if newX < 1 then newX = 1 end
        if newY < 1 then newY = 1 end
        local maxWidth, maxHeight = gpu.maxResolution()
        if newX + self.width - 1 > maxWidth then newX = maxWidth - self.width + 1 end
        if newY + self.height - 1 > maxHeight then newY = maxHeight - self.height + 1 end
        
        self.x = newX
        self.y = newY
        return true
    end
    return false
end

function Window:handleMouseUp(mx, my, button)
    if self.isDragging then
        self.isDragging = false
        return true
    end
    return false
end

function Window:close()
    self.isVisible = false
end

return Window