-- installer.lua
-- Інсталятор для Glass OS в OpenComputers (без прошивки BIOS)

local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local io = require("io") -- Забезпечуємо завантаження io
local event = require("event") -- Для waitForKey

-- Налаштування репозиторію
local GITHUB_USER = "FixlutGames21" -- Ваш GitHub username
local GITHUB_REPO = "Glass-OS"     -- Назва вашого репозиторію на GitHub
local GITHUB_BRANCH = "main"        -- Зазвичай "main" або "master"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local TARGET_HDD_DIR = "/glassos" -- Директорія встановлення на HDD

-- Список файлів, які потрібно завантажити
local FILES_TO_DOWNLOAD = {
    "main.lua",
    "lib/colors.lua",
    "lib/drawing.lua",
    "lib/utils.lua",
    "gui_elements/window.lua",
    "installer.lua", -- Включаємо сам інсталятор для оновлення
}

-- Допоміжна функція для очищення екрану та виводу повідомлення
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
    print(msg)
}

local function waitForKey()
    print("\nНатисніть будь-яку клавішу для продовження...")
    event.pull("key_down")
end

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
    printMessage("Починаю встановлення Glass OS...")
    print("Це встановлення не модифікує BIOS. Glass OS запускатиметься з OpenOS.")

    -- 1. Знаходимо основний жорсткий диск (ретельна перевірка)
    local hdd = nil
    for address in component.list("filesystem") do
        local fs = component.get(address)
        -- Перевіряємо, що це форматований, не тільки для читання, і є достатньо місця
        -- Також перевіряємо, що це не tmpfs або інші віртуальні файлові системи
        if fs.isFormatted and not fs.isReadOnly and fs.spaceUsed() ~= nil then -- spaceUsed() повертає nil для віртуальних
             hdd = fs
             break
        end
    end

    if not hdd then
        printMessage("Помилка: Не знайдено жорсткий диск для встановлення Glass OS. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        os.exit()
    end
    local hddPath = hdd.path()
    if not hddPath then
        printMessage("Помилка: Не вдалося отримати кореневий шлях жорсткого диска. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        os.exit()
    end

    printMessage("Знайдено жорсткий диск: " .. (hdd.getLabel() or "Без мітки") .. "...")
    waitForKey()

    -- 2. Запитуємо користувача про форматування HDD
    printMessage("УВАГА: Встановлення Glass OS потребує форматування жорсткого диска '" .. (hdd.getLabel() or "Без мітки") .. "'.\n" ..
                 "УСІ ДАНІ НА ЖОРСТКОМУ ДИСКУ БУДУТЬ ВИДАЛЕНІ!\n\n" ..
                 "Ви впевнені, що хочете продовжити? (yes/no)")
    local input = io.read()
    if string.lower(input) ~= "yes" then
        printMessage("Встановлення скасовано користувачем.")
        computer.beep()
        os.sleep(2)
        os.exit()
    end

    printMessage("Форматую жорсткий диск '" .. (hdd.getLabel() or "Без мітки") .. "'...")
    local success, err = pcall(hdd.format)
    if not success then
        printMessage("Помилка форматування диска: " .. tostring(err) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        os.exit()
    end
    printMessage("Форматування завершено. Жорсткий диск очищено.")
    waitForKey()

    -- 3. Копіюємо файли на жорсткий диск
    printMessage("Копіюю файли Glass OS на жорсткий диск...")
    local oldPath = filesystem.path() -- Зберігаємо поточний шлях

    local successCopy, errCopy = pcall(function()
        -- Створюємо основну директорію для Glass OS на HDD
        if not filesystem.exists(TARGET_HDD_DIR, hdd.address) then
            local created, createErr = filesystem.makeDirectory(TARGET_HDD_DIR, hdd.address)
            if not created then
                error("Не вдалося створити директорію '" .. TARGET_HDD_DIR .. "' на HDD: " .. createErr)
            end
        end
        filesystem.changeDirectory(TARGET_HDD_DIR, hdd.address) -- Змінюємо поточну директорію на HDD

        local function copyRecursive(srcComponent, srcPath, destComponent, destPath)
            local entries = filesystem.list(srcPath, srcComponent.address)
            for name, isDir in pairs(entries) do
                local currentSrc = filesystem.concat(srcPath, name)
                local currentDest = filesystem.concat(destPath, name)

                if isDir then
                    if not filesystem.exists(currentDest, destComponent.address) then
                        local created, createErr = filesystem.makeDirectory(currentDest, destComponent.address)
                        if not created then
                            error("Не вдалося створити директорію '" .. currentDest .. "' на HDD: " .. createErr)
                        end
                    end
                    copyRecursive(srcComponent, currentSrc, destComponent, currentDest)
                else
                    -- Завантажуємо файли з GitHub безпосередньо в потрібну директорію на HDD
                    local fullUrl = BASE_URL .. string.gsub(currentSrc, hddPath .. TARGET_HDD_DIR .. "/", "") -- Отримуємо відносний шлях для URL
                    local relativeLocalPath = filesystem.relativePath(currentSrc, filesystem.concat(hddPath, TARGET_HDD_DIR))
                    downloadFile(fullUrl, relativeLocalPath)
                end
            end
        end
        
        -- Копіюємо всі файли з FILES_TO_DOWNLOAD до TARGET_HDD_DIR
        for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
            local fullUrl = BASE_URL .. fileRelativePath
            local localPath = fileRelativePath -- Це відносний шлях у рамках TARGET_HDD_DIR

            local dirName = filesystem.directory(localPath)
            if dirName ~= "" then
                local currentDirSegment = ""
                for segment in string.gmatch(dirName, "[^/\\]+") do -- Також враховуємо зворотні слеші
                    currentDirSegment = filesystem.concat(currentDirSegment, segment)
                    if not filesystem.exists(currentDirSegment, hdd.address) then -- Перевіряємо існування в поточній директорії (що на HDD)
                        local created, createErr = filesystem.makeDirectory(currentDirSegment, hdd.address)
                        if not created then
                            error("Не вдалося створити піддиректорію '" .. currentDirSegment .. "' на HDD: " .. createErr)
                        end
                    end
                end
            end
            downloadFile(fullUrl, localPath)
        end

    end)

    filesystem.changeDirectory(oldPath) -- Повертаємося до попередньої директоре

    if not successCopy then
        printMessage("Помилка копіювання файлів: " .. tostring(errCopy) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        os.exit()
    end
    printMessage("Копіювання файлів Glass OS завершено.")
    waitForKey()

    printMessage("\n[ВСТАНОВЛЕННЯ ЗАВЕРШЕНО]: Glass OS успішно встановлено на жорсткий диск.")
    print("Щоб запустити Glass OS, перезавантажте комп'ютер у OpenOS і виконайте команду:")
    print("lua " .. TARGET_HDD_DIR .. "/main.lua")
    computer.beep()
    os.sleep(5)
    os.exit()
end

-- Запуск інсталятора (з обробкою помилок)
local success, errorMessage = pcall(installGlassOS)
if not success then
    printMessage("\n[ПОМИЛКА ВСТАНОВЛЕННЯ]: " .. tostring(errorMessage))
    computer.beep()
end