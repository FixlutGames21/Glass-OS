-- installer.lua
-- Інсталятор для Glass OS в OpenComputers (з підтримкою дискети та прошивки BIOS)

local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local io = require("io") -- Забезпечуємо завантаження io

-- Налаштування репозиторію
local GITHUB_USER = "FixlutGames21" -- Ваш GitHub username (збережено з профілю)
local GITHUB_REPO = "Glass-OS"     -- Назва вашого репозиторію на GitHub
local GITHUB_BRANCH = "main"        -- Зазвичай "main" або "master"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local FLOPPY_LABEL = "GlassOS_Install" -- Мітка для дискети. Важливо, щоб дискета була вставлена!

-- Список файлів, які потрібно завантажити (додаємо bios.lua)
local FILES_TO_DOWNLOAD = {
    "main.lua",
    "lib/colors.lua",
    "lib/drawing.lua",
    "lib/utils.lua",
    "gui_elements/window.lua",
    "installer.lua",
    "bios.lua", -- Новий файл BIOS!
}

-- Допоміжна функція для завантаження файлів
local function downloadFile(url, path)
    print("Завантажую: " .. url)
    local success, data = pcall(function()
        local handle = shell.open(url)
        local content = handle:readAll()
        handle:close()
        return content
    end)

    if not success or not data then
        error("Не вдалося завантажити " .. url .. ". Можливо, немає доступу до інтернету або файл не існує: " .. tostring(data))
    end

    local fileHandle, errorMsg = io.open(path, "w")
    if not fileHandle then
        error("Не вдалося створити файл " .. path .. ": " .. errorMsg)
    end
    fileHandle:write(data)
    fileHandle:close()
    print("Збережено: " .. path)
end

-- Основна логіка встановлення
local function installGlassOS()
    print("Починаю встановлення Glass OS...")

    -- 1. Знаходимо дискету
    local floppy = component.get(component.list("filesystem", true)())
    if not floppy then
        error("Помилка: Не знайдено дискету. Будь ласка, вставте чисту дискету в комп'ютер.")
    end
    print("Знайдено дискету: " .. (floppy.getLabel() or "Без мітки")) -- Додано перевірку на nil для getLabel

    -- 2. Створюємо директорію на дискеті (або використовуємо корінь)
    local targetFloppyDir = floppy.path() .. "/" .. FLOPPY_LABEL
    if not filesystem.exists(targetFloppyDir, floppy.address) then
        print("Створюю директорію на дискеті: " .. targetFloppyDir)
        if not filesystem.makeDirectory(targetFloppyDir, floppy.address) then
            error("Не вдалося створити директорію на дискеті: " .. targetFloppyDir)
        end
    end
    
    -- 3. Завантажуємо всі файли на дискету
    local oldPath = filesystem.path()
    -- !!! Виправлено: використано floppy.address для зміни директорії на дискету
    filesystem.changeDirectory(targetFloppyDir, floppy.address) 
    
    for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
        -- Перевірка на nil або порожній шлях
        if not fileRelativePath or fileRelativePath == "" then
            print("Попередження: Пропущено порожній шлях до файлу в FILES_TO_DOWNLOAD.")
            goto continue
        end

        local fullUrl = BASE_URL .. fileRelativePath
        local localPath = fileRelativePath

        -- Перевіряємо та створюємо всі необхідні піддиректорії на дискеті
        local dirName = filesystem.directory(localPath)
        if dirName ~= "" and not filesystem.exists(dirName, floppy.address) then
            print("Створюю піддиректорію на дискеті: " .. dirName)
            local currentDir = ""
            for segment in string.gmatch(dirName, "[^/]+") do
                currentDir = currentDir .. segment .. "/"
                if not filesystem.exists(currentDir, floppy.address) then
                    local created, createErr = filesystem.makeDirectory(currentDir, floppy.address)
                    if not created then
                        error("Не вдалося створити піддиректорію на дискеті " .. currentDir .. ": " .. createErr)
                    end
                end
            end
        end

        downloadFile(fullUrl, localPath)
        ::continue::
    end

    filesystem.changeDirectory(oldPath) -- Повертаємося до попередньої директорії

    print("\nВсі файли Glass OS завантажено на дискету.")
    print("Тепер прошиваю BIOS комп'ютера для завантаження з дискети...")

    -- 4. Прошиваємо BIOS
    local eeprom = component.eeprom
    if not eeprom then
        error("Помилка: EEPROM (BIOS) не знайдено.")
    end

    -- Створюємо скрипт для завантаження з дискети та запуску bios.lua
    local bootScript = [[
        local component = require("component")
        local filesystem = require("filesystem")
        local shell = require("shell")
        local io = require("io") -- Забезпечуємо завантаження io

        local floppy = component.get(component.list("filesystem", true)())
        if not floppy then
            io.write("Помилка: Дискета не знайдена. Будь ласка, вставте дискету з інсталятором Glass OS.\n") -- Використовуємо io.write
            io.flush() -- Явний flush
            shell.execute("reboot")
        end

        local biosPath = floppy.path() .. "/]] .. FLOPPY_LABEL .. [[/bios.lua"
        if not filesystem.exists(biosPath, floppy.address) then
            io.write("Помилка: Файл 'bios.lua' не знайдено на дискеті за шляхом: " .. biosPath .. "\n") -- Використовуємо io.write
            io.flush() -- Явний flush
            shell.execute("reboot")
        end

        io.write("Запускаю інсталятор Glass OS з дискети...\n") -- Використовуємо io.write
        io.flush() -- Явний flush
        shell.execute("lua " .. biosPath)
        io.write("Після завершення інсталяції, будь ласка, перезавантажте комп'ютер.\n") -- Використовуємо io.write
        io.flush() -- Явний flush
    ]]

    eeprom.set(bootScript)
    print("BIOS успішно прошито! Комп'ютер тепер завантажуватиметься з дискети.")
    print("Після перезавантаження, дискета буде форматувати жорсткий диск та встановлювати ОС.")
    print("\n[ВСТАНОВЛЕННЯ ЗАВЕРШЕНО]: Будь ласка, перезавантажте комп'ютер (команда 'reboot').")
end

-- Запуск інсталятора (з обробкою помилок)
local success, errorMessage = pcall(installGlassOS)
if not success then
    print("\n[ПОМИЛКА ВСТАНОВЛЕННЯ]: " .. tostring(errorMessage))
    computer.beep()
end