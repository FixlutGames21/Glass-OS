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

-- Допоміжна функція для безпечного очищення екрану та виводу повідомлення
local function printMessage(msg)
    local gpu = component.gpu
    if gpu then
        local success, errMsg = pcall(gpu.setResolution, gpu.maxResolution())
        if not success then
             pcall(gpu.setResolution, 80, 25)
        end
        local maxWidth, maxHeight = gpu.getResolution()
        pcall(gpu.setBackground, 0x000000) -- Чорний фон
        pcall(gpu.setForeground, 0xFFFFFF) -- Білий текст
        pcall(gpu.fill, 1, 1, maxWidth, maxHeight, " ")
    end
    print(msg)
end

local function waitForKey()
    print("\nНатисніть будь-яку клавішу для продовження...")
    event.pull("key_down")
end

-- Допоміжна функція для завантаження файлів
local function downloadFile(url, path)
    print("Завантажую: " .. url)
    local handle, err = require("internet").request(url)
    if not handle then
        error("Не вдалося відкрити URL: " .. tostring(err))
    end

    local content = ""
    for chunk in handle do
        content = content .. chunk
    end

    local fileHandle, errorMsg = io.open(path, "w")
    if not fileHandle then
        error("Не вдалося створити файл " .. path .. ": " .. errorMsg)
    end
    fileHandle:write(content)
    fileHandle:close()
    print("Збережено: " .. path)
end

-- Основна логіка встановлення
local function installGlassOS()
    printMessage("Починаю встановлення Glass OS...")
    print("Це встановлення не модифікує BIOS. Glass OS запускатиметься з OpenOS.")

    -- 1. Знаходимо основний жорсткий диск
    local hdd = nil
    local hddAddress = nil
    for address in component.list("filesystem") do
        local fs = component.proxy(address)
        if fs.isFormatted and not fs.isReadOnly then
            hdd = fs
            hddAddress = address
            break
        end
    end

    if not hdd then
        printMessage("Помилка: Не знайдено жодного жорсткого диска для встановлення Glass OS. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end

    local hddLabel = hdd.getLabel and (hdd.getLabel() or "Без мітки") or "Невідомий"

    printMessage("Знайдено жорсткий диск: " .. hddLabel .. " (" .. hddAddress .. ")...")
    waitForKey()

    -- 2. Запитуємо користувача про форматування HDD
    printMessage("УВАГА: Встановлення Glass OS потребує форматування жорсткого диска '" .. hddLabel .. "'.\n" ..
                 "УСІ ДАНІ НА ЖОРСТКОМУ ДИСКУ БУДУТЬ ВИДАЛЕНІ!\n\n" ..
                 "Ви впевнені, що хочете продовжити? (yes/no)")
    local input = io.read()
    if string.lower(input) ~= "yes" then
        printMessage("Встановлення скасовано користувачем.")
        computer.beep()
        os.sleep(2)
        computer.shutdown()
    end

    printMessage("Форматую жорсткий диск '" .. hddLabel .. "'...")
    local success, err = pcall(hdd.format)
    if not success then
        printMessage("Помилка форматування диска: " .. tostring(err) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end
    printMessage("Форматування завершено. Жорсткий диск очищено.")
    waitForKey()

    -- 3. Копіюємо файли на жорсткий диск
    printMessage("Копіюю файли Glass OS на жорсткий диск...")
    for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
        local fullUrl = BASE_URL .. fileRelativePath
        local localPath = TARGET_HDD_DIR .. "/" .. fileRelativePath

        local dirName = localPath:match("(.*/)")
        if dirName and not filesystem.exists(dirName) then
            filesystem.makeDirectory(dirName)
        end
        downloadFile(fullUrl, localPath)
    end

    printMessage("Копіювання файлів Glass OS завершено.")
    waitForKey()

    printMessage("\n[ВСТАНОВЛЕННЯ ЗАВЕРШЕНО]: Glass OS успішно встановлено на жорсткий диск.")
    print("Щоб запустити Glass OS, перезавантажте комп'ютер у OpenOS і виконайте команду:")
    print("lua " .. TARGET_HDD_DIR .. "/main.lua")
    computer.beep()
    os.sleep(5)
    computer.shutdown()
end

-- Запуск інсталятора (з обробкою помилок)
local success, errorMessage = pcall(installGlassOS)
if not success then
    printMessage("\n[ПОМИЛКА ВСТАНОВЛЕННЯ]: " .. tostring(errorMessage))
    computer.beep()
    computer.shutdown()
end
