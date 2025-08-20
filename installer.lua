-- installer.lua
-- Інсталятор для Glass OS в OpenComputers (без прошивки BIOS)

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem") -- Змінено на 'filesystem' для уникнення конфлікту з локальною 'fs'
local shell = require("shell")
local term = require("term") -- Для терміналу
local event = require("event") -- Для waitForKey
local io = require("io")
local os = require("os")

-- Налаштування репозиторію
local GITHUB_USER = "FixlutGames21" -- Ваш GitHub username
local GITHUB_REPO = "Glass-OS"     -- Назва вашого репозиторію на GitHub
local GITHUB_BRANCH = "main"        -- Зазвичай "main" або "master"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local TARGET_HDD_DIR = "/glassos" -- Директорія встановлення на HDD (змінено, щоб ставити в окрему папку)

-- Допоміжна функція для безпечного очищення екрану та виводу повідомлення
local function printMessage(msg)
    local gpu = component.gpu
    if gpu then
        -- Спроба встановити максимальну роздільну здатність, потім стандартну
        local successRes, errMsgRes = pcall(gpu.setResolution, gpu, gpu.maxResolution())
        if not successRes then
             pcall(gpu.setResolution, gpu, 80, 25) -- Стандартна роздільна здатність
        end
        local maxWidth, maxHeight = gpu.getResolution()
        pcall(gpu.setBackground, gpu, 0x000000) -- Чорний фон
        pcall(gpu.setForeground, gpu, 0xFFFFFF) -- Білий текст
        pcall(gpu.fill, gpu, 1, 1, maxWidth, maxHeight, " ")
    else
        -- Якщо GPU недоступний, просто очистити термінал і вивести повідомлення
        term.clear()
    end
    print("[GlassOS Installer] " .. msg)
end

local function waitForKey()
    print("\nНатисніть будь-яку клавішу для продовження...")
    event.pull("key_down")
end

-- Допоміжна функція для рекурсивного створення батьківських директорій
local function makeParentDirectory(filePath)
    local dirName = filesystem.directory(filePath)
    if dirName ~= "" and not filesystem.exists(dirName) then
        local currentDirSegment = ""
        for segment in string.gmatch(dirName, "[^/\\]+") do
            currentDirSegment = filesystem.concat(currentDirSegment, segment)
            if not filesystem.exists(currentDirSegment) then
                local created, createErr = filesystem.makeDirectory(currentDirSegment)
                if not created then
                    error("Не вдалося створити директорію '" .. currentDirSegment .. "': " .. createErr)
                end
            end
        end
    end
end

-- Допоміжна функція для завантаження файлів (використовуємо shell.open)
local function downloadFile(url, path)
    print("Завантажую: " .. url)
    local success, data = pcall(function()
        local handle = shell.open(url)
        if not handle then error("Не вдалося відкрити URL. Можливо, немає мережевого підключення або URL неправильний.") end
        local content = handle:readAll()
        handle:close()
        return content
    end)

    if not success or not data then
        error("Не вдалося завантажити " .. url .. ". Можливо, немає доступу до інтернету або файл не існує: " .. tostring(data))
    end

    -- Створення батьківських директорій перед записом файлу
    makeParentDirectory(path)

    local fileHandle, errorMsg = io.open(path, "w")
    if not fileHandle then
        error("Не вдалося створити файл " .. path .. ": " .. errorMsg)
    end
    fileHandle:write(data)
    fileHandle:close()
    print("Збережено: " .. path)
end

-- Функція для пошуку HDD
local function findHdd()
    local hdd = nil
    local hddAddress = nil
    local rootFsAddress = component.list("filesystem", true)() -- Отримуємо адресу кореневої файлової системи

    -- Спершу шукаємо додатковий диск (не кореневий)
    for address in component.list("filesystem") do
        local fs_comp = component.get(address)
        if fs_comp and fs_comp.isFormatted and not fs_comp.isReadOnly then
            if address ~= rootFsAddress then -- Пропускаємо диск, з якого завантажились
                hdd = fs_comp
                hddAddress = address
                return hdd, hddAddress
            end
        end
    end

    -- Якщо не знайшли додаткового диска, пропонуємо використовувати кореневий
    if rootFsAddress then
        hdd = component.get(rootFsAddress)
        hddAddress = rootFsAddress
        printMessage("Попередження: Не знайдено іншого диска для встановлення. Буде використано диск, з якого завантажено OpenOS.")
        print("УВАГА: Це призведе до ВИДАЛЕННЯ OpenOS! Переконайтеся, що це те, що ви хочете.")
        waitForKey()
        return hdd, hddAddress
    end

    return nil, nil
end

-- Основна логіка встановлення
local function installGlassOS()
    printMessage("Починаю встановлення Glass OS...")
    print("Це встановлення не модифікує BIOS. Glass OS запускатиметься з OpenOS.")

    local hdd, hddAddress = findHdd()

    if not hdd then
        printMessage("Помилка: Не знайдено жодного жорсткого диска для встановлення Glass OS. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end

    local hddLabel = ""
    if hdd.getLabel then
        hddLabel = hdd.getLabel() or "Без мітки"
    else
        hddLabel = "Невідомий (без getLabel)"
    end
    
    printMessage("Знайдено жорсткий диск: " .. hddLabel .. " (Адреса: " .. tostring(hddAddress) .. ")...")
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
    local successFormat, errFormat = pcall(hdd.format) -- Використовуємо метод format() самого HDD
    if not successFormat then
        printMessage("Помилка форматування диска: " .. tostring(errFormat) .. ". Можливо, диск захищений від запису або пошкоджений. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end
    printMessage("Форматування завершено. Жорсткий диск очищено.")
    waitForKey()

    -- Змінюємо поточну директорію на HDD для зручності
    local oldPath = filesystem.path() -- Зберігаємо поточний шлях
    local successCd, cdErr = pcall(filesystem.changeDirectory, filesystem, TARGET_HDD_DIR, hddAddress)
    if not successCd then
        -- Якщо TARGET_HDD_DIR ще не існує, спробувати створити його та перейти туди
        local created, createErr = pcall(filesystem.makeDirectory, filesystem, TARGET_HDD_DIR, hddAddress)
        if not created then
            printMessage("Помилка: Не вдалося створити директорію встановлення: " .. tostring(createErr))
            computer.beep()
            os.sleep(5)
            computer.shutdown()
        end
        successCd, cdErr = pcall(filesystem.changeDirectory, filesystem, TARGET_HDD_DIR, hddAddress)
        if not successCd then
            printMessage("Помилка: Не вдалося перейти в директорію встановлення: " .. tostring(cdErr))
            computer.beep()
            os.sleep(5)
            computer.shutdown()
        end
    end

    -- Список файлів для завантаження (оновлений відповідно до Glass-OS)
    local FILES_TO_DOWNLOAD = {
        "boot.lua", -- Змінено з main.lua на boot.lua для завантажувача
        "system/core.lua",
        "system/gui.lua",
        "system/shell.lua",
        "lib/colors.lua", -- З попередньої версії
        "lib/drawing.lua", -- З попередньої версії
        "lib/utils.lua",   -- З попередньої версії
        "gui_elements/window.lua", -- З попередньої версії
        "installer.lua", -- Включаємо сам інсталятор для оновлення
    }

    printMessage("Копіюю файли Glass OS на жорсткий диск...")
    for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
        local fullUrl = BASE_URL .. fileRelativePath
        local localPath = fileRelativePath -- Це відносний шлях у рамках TARGET_HDD_DIR
        downloadFile(fullUrl, localPath)
    end

    -- Намагаємося повернутися до попередньої директорії або до кореня
    local successReturn, errReturn = pcall(filesystem.changeDirectory, filesystem, oldPath)
    if not successReturn then
        pcall(filesystem.changeDirectory, filesystem, "/")
    end

    printMessage("\n[ВСТАНОВЛЕННЯ ЗАВЕРШЕНО]: Glass OS успішно встановлено на жорсткий диск.")
    print("Щоб запустити Glass OS, перезавантажте комп'ютер у OpenOS і виконайте команду:")
    print("lua " .. TARGET_HDD_DIR .. "/boot.lua") -- Змінено на boot.lua
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