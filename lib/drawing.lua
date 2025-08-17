-- lib/drawing.lua
-- Містить допоміжні функції для малювання GUI елементів

local component = require("component")
local gpu = component.gpu
local colors = require("lib.colors")

local M = {}

local _maxWidth, _maxHeight

function M.init(width, height)
    _maxWidth = width
    _maxHeight = height
end

function M.clearScreen()
    gpu.setBackground(colors.DESKTOP_BLUE)
    gpu.setForeground(colors.WHITE)
    gpu.fill(1, 1, _maxWidth, _maxHeight, " ")
end

function M.draw3dButton(x, y, btnWidth, btnHeight, text, isPressed)
    local bg_color = colors.TASKBAR_GREY
    local text_color = colors.BLACK

    gpu.setBackground(bg_color)
    gpu.fill(x, y, btnWidth, btnHeight, " ")

    if isPressed then
        gpu.setBackground(colors.BUTTON_3D_DARK)
        gpu.set(x, y, " ")
        gpu.fill(x, y + 1, 1, btnHeight - 1, " ")
        gpu.fill(x + 1, y, btnWidth - 1, 1, " ")
    else
        gpu.setBackground(colors.BUTTON_3D_LIGHT)
        gpu.set(x, y, " ")
        gpu.fill(x, y + 1, 1, btnHeight - 1, " ")
        gpu.fill(x + 1, y, btnWidth - 1, 1, " ")

        gpu.setBackground(colors.BUTTON_3D_DARK)
        gpu.set(x + btnWidth - 1, y + btnHeight - 1, " ")
        gpu.fill(x + btnWidth - 1, y + 1, 1, btnHeight - 2, " ")
        gpu.fill(x + 1, y + btnHeight - 1, btnWidth - 2, 1, " ")
    end

    gpu.setForeground(text_color)
    gpu.setBackground(bg_color)
    local textX = x + math.floor((btnWidth - #text) / 2)
    local textY = y + math.floor(btnHeight / 2)
    gpu.set(textX, textY, text)
end

function M.drawWindow(x, y, width, height, title, isActive)
    local border_color = colors.WINDOW_BORDER
    local title_bg_color = isActive and colors.WINDOW_TITLE_ACTIVE or colors.WINDOW_TITLE_INACTIVE
    local title_text_color = colors.WHITE
    local content_bg_color = colors.MENU_BG

    gpu.setBackground(border_color)
    gpu.fill(x, y, width, height, " ")

    gpu.setBackground(title_bg_color)
    gpu.setForeground(title_text_color)
    gpu.fill(x + 1, y, width - 2, 1, " ")
    gpu.set(x + 2, y, title:sub(1, width - 6))

    local closeBtnX = x + width - 4
    local closeBtnY = y
    M.draw3dButton(closeBtnX, closeBtnY, 3, 1, " X ", false)

    gpu.setBackground(content_bg_color)
    gpu.fill(x + 1, y + 1, width - 2, height - 2, " ")
end

return M