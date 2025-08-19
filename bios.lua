-- bios.lua
-- Скрипт, що запускається з дискети після прошивки BIOS.
-- Відповідає за форматування HDD та встановлення Glass OS.

local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local event = require("event")
local io = require("io")

-- Налаштування (мають співпадати з installer.lua)
local FLOPPY_LABEL = "GlassOS_Install"
local TARGET_HDD_DIR = "/glassos" -- Директорія на HDD

local function clearScreen()
    local gpu = component.gpu
    if gpu then
        local maxWidth, maxHeight = gpu.maxResolution()
        gpu.setResolution(maxWidth, maxHeight)
        gpu.setBackground(0x000000) -- Чорний фон
        gpu.setForeground(0xFFFFFF) -- Білий текст
        gpu.fill(1, 1, maxWidth, maxHeight, " ")
    end
end

local function printMessage(msg)
    clearScreen()
    io.stdout:write(msg .. "\n")
    io.stdout:flush()
end

local function waitForKey()
    io.stdout:write("\nНатисніть будь-яку клавішу для продовження...\n")
    io.stdout:flush()
    event.pull("key_down")
end

local function installFromFloppy()
    printMessage("Починаю встановлення Glass OS з дискети...")

    -- 1. Знаходимо дискету
    local floppy = component.get(component.list("filesystem", true)())
    if not floppy or floppy.getLabel() ~= FLOPPY_LABEL then
        printMessage("Помилка: Не знайдено дискету з інсталятором ('" .. FLOPPY_LABEL .. "'). Перезавантаження.")
        computer.beep()
        os.sleep(5)
        shell.execute("reboot")
    end
    local floppyPath = floppy.path() .. "/" .. FLOPPY_LABEL

    -- 2. Знаходимо основний жорсткий диск
    local hdd = nil
    for address in component.list("filesystem") do
        local fs = component.get(address)
        if fs.isFormatted and not fs.isReadOnly and fs.uuid() ~= floppy.uuid() then -- Шукаємо форматований HDD, який не є дискетою
            hdd = fs
            break
        end
    end

    if not hdd then
        printMessage("Помилка: Не знайдено жорсткий диск для встановлення Glass OS. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        shell.execute("reboot")
    end
    local hddPath = hdd.path()

    printMessage("Знайдено дискету: '" .. floppy.getLabel() .. "' та жорсткий диск: " .. hdd.getLabel() .. "...")
    waitForKey()

    -- 3. Форматуємо жорсткий диск
    printMessage("Форматую жорсткий диск '" .. hdd.getLabel() .. "'...")
    local success, err = pcall(hdd.format)
    if not success then
        printMessage("Помилка форматування диска: " .. tostring(err) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        shell.execute("reboot")
    end
    printMessage("Форматування завершено. Жорсткий диск очищено.")
    waitForKey()

    -- 4. Копіюємо файли з дискети на жорсткий диск
    printMessage("Копіюю файли Glass OS з дискети на жорсткий диск...")
    local successCopy, errCopy = pcall(function()
        local function copyRecursive(srcPath, destPath)
            local entries = filesystem.list(srcPath, floppy.address)
            for name, isDir in pairs(entries) do
                local currentSrc = filesystem.concat(srcPath, name)
                local currentDest = filesystem.concat(destPath, name)

                if isDir then
                    if not filesystem.exists(currentDest, hdd.address) then
                        filesystem.makeDirectory(currentDest, hdd.address)
                    end
                    copyRecursive(currentSrc, currentDest)
                else
                    local content = filesystem.read(currentSrc, floppy.address)
                    filesystem.write(currentDest, hdd.address, content)
                end
            end
        end
        
        filesystem.makeDirectory(TARGET_HDD_DIR, hdd.address) -- Створюємо основну директорію на HDD
        copyRecursive(floppyPath, TARGET_HDD_DIR)
    end)

    if not successCopy then
        printMessage("Помилка копіювання файлів: " .. tostring(errCopy) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        shell.execute("reboot")
    end
    printMessage("Копіювання файлів завершено.")
    waitForKey()

    -- 5. Перепрошиваємо BIOS для завантаження з HDD
    printMessage("Перепрошиваю BIOS для завантаження Glass OS з жорсткого диска...")
    local eeprom = component.eeprom
    if not eeprom then
        printMessage("Помилка: EEPROM (BIOS) не знайдено. Неможливо змінити завантаження.")
        computer.beep()
        os.sleep(5)
        shell.execute("reboot")
    end

    local bootScriptHDD = [[
        local component = require("component")
        local shell = require("shell")
        local filesystem = require("filesystem")

        -- Знаходимо жорсткий диск з встановленою ОС
        local hddFs = nil
        for address in component.list("filesystem") do
            local fs = component.get(address)
            if fs.isFormatted and not fs.isReadOnly and filesystem.exists("]] .. TARGET_HDD_DIR .. [[/main.lua", fs.address) then
                hddFs = fs
                break
            end
        end

        if not hddFs then
            io.stderr:write("Помилка: Жорсткий диск з Glass OS не знайдено. Перезавантаження в OpenOS.\n")
            shell.execute("reboot") -- Перезавантажуємо, можливо, повернемося до OpenOS
        else
            io.stderr:write("Завантажую Glass OS з жорсткого диска...\n")
            shell.execute("lua " .. hddFs.path() .. "]] .. TARGET_HDD_DIR .. [[/main.lua")
        end
    ]]

    eeprom.set(bootScriptHDD)
    printMessage("BIOS успішно прошито! Glass OS встановлено на жорсткий диск.")
    printMessage("Будь ласка, вийміть дискету та перезавантажте комп'ютер.")
    computer.beep()
    os.sleep(5)
    printMessage("Встановлення завершено!")
    os.exit() -- Завершуємо роботу bios.lua
end

-- Запуск інсталяції з дискети
local success, errorMessage = pcall(installFromFloppy)
if not success then
    printMessage("\n[ПОМИЛКА ВСТАНОВЛЕННЯ З ДИСКЕТИ]: " .. tostring(errorMessage))
    computer.beep()
    os.sleep(5)
    shell.execute("reboot")
end