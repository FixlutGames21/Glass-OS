-- lib/utils.lua
-- Містить загальні допоміжні функції

local M = {}

function M.isClicked(mx, my, elX, elY, elWidth, elHeight)
    return mx >= elX and mx < elX + elWidth and my >= elY and my < elY + elHeight
end

return M