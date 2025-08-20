-- installer.lua
-- Інсталятор для Glass OS в OpenComputers (без прошивки BIOS)

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local shell = require("shell")
local term = require("term")
local event = require("event")
local io = require("io")
local os = require("os")

-- Налаштування репозиторію
local GITHUB_USER = "FixlutGames21" -- Ваш GitHub username
local GITHUB_REPO = "Glass-OS"     -- Назва вашого репозиторію на GitHub
local GITHUB_BRANCH = "main"        -- Зазвичай "main" або "master"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local TARGET_HDD_DIR = "/glassos" -- Директорія встановлення на HDD

-- Допоміжна функція для безпечного очищення екрану та виводу повідомлення
local function printMessage(msg)
    local gpu = component.gpu
    if gpu then
        -- Спроба встановити максимальну роздільну здатність, потім стандартну
        local successRes, errMsgRes = pcall(gpu.setResolution, gpu, gpu.maxResolution())
        if not successRes then
             pcall(gpu.setResolution, gpu, 80, 25) -- Стандартна роздільна здатність
        end
        local maxWidth, maxHeight = pcall(gpu.getResolution, gpu) -- Додати pcall і об'єкт gpu
        if not maxWidth then maxWidth, maxHeight = 80, 25 end -- Запасний варіант
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

-- Допоміжна функція для рекурсивного видалення директорії
local function deleteDirectoryRecursive(path)
    if not filesystem.exists(path) then return true end

    -- Отримуємо список вмісту директорії
    local list = {}
    for entry in filesystem.list(path) do
        table.insert(list, entry)
    end

    -- Видаляємо кожен елемент
    for _, entry in ipairs(list) do
        local fullPath = filesystem.concat(path, entry)
        if filesystem.isDirectory(fullPath) then
            local ok, err = deleteDirectoryRecursive(fullPath)
            if not ok then return false, err end
        else
            local ok, err = pcall(filesystem.remove, filesystem, fullPath)
            if not ok then return false, err end
        end
    end

    -- Видаляємо саму директорію після видалення її вмісту
    local ok, err = pcall(filesystem.remove, filesystem, path)
    if not ok then return false, err end

    return true
end


-- Допоміжна функція для рекурсивного створення батьківських директорій
local function makeParentDirectory(filePath, targetFsAddress)
    local dirName = filesystem.directory(filePath)
    if dirName == "" then return true end -- Це файл у кореневій директорії

    -- Змінюємо контекст файлової системи, якщо вказана адреса
    local originalFsAddress = filesystem.path() -- Зберігаємо поточний шлях
    if targetFsAddress and targetFsAddress ~= originalFsAddress then
        local success, err = filesystem.changeDirectory(targetFsAddress) -- Тимчасово змінюємо FS контекст
        if not success then error("Не вдалося змінити FS контекст: " .. tostring(err)) end
    end

    local currentDirSegment = ""
    for segment in string.gmatch(dirName, "[^/\\]+") do
        currentDirSegment = filesystem.concat(currentDirSegment, segment)
        if not filesystem.exists(currentDirSegment) then
            local created, createErr = filesystem.makeDirectory(currentDirSegment)
            if not created then
                -- Повертаємо FS контекст перед викиданням помилки
                if targetFsAddress and targetFsAddress ~= originalFsAddress then
                    filesystem.changeDirectory(originalFsAddress)
                end
                error("Не вдалося створити директорію '" .. currentDirSegment .. "': " .. createErr)
            end
        end
    end

    -- Повертаємо FS контекст
    if targetFsAddress and targetFsAddress ~= originalFsAddress then
        filesystem.changeDirectory(originalFsAddress)
    end
    return true
end

-- Допоміжна функція для завантаження файлів (використовуємо shell.open)
local function downloadFile(url, path, targetFsAddress)
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
    local ok, err = makeParentDirectory(path, targetFsAddress)
    if not ok then error("Помилка створення директорій: " .. tostring(err)) end

    -- Змінюємо контекст файлової системи для запису, якщо вказана адреса
    local originalFsPath = filesystem.path()
    if targetFsAddress then
        local success, err = filesystem.changeDirectory(targetFsAddress)
        if not success then error("Не вдалося змінити FS контекст для запису: " .. tostring(err)) end
    end
    
    local fileHandle, errorMsg = io.open(path, "w")
    if not fileHandle then
        -- Повертаємо FS контекст перед викиданням помилки
        if targetFsAddress then filesystem.changeDirectory(originalFsPath) end
        error("Не вдалося створити файл " .. path .. ": " .. errorMsg)
    end
    fileHandle:write(data)
    fileHandle:close()

    -- Повертаємо FS контекст
    if targetFsAddress then
        filesystem.changeDirectory(originalFsPath)
    end

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
    printMessage("УВАГА: Встановлення Glass OS потребує очищення жорсткого диска '" .. hddLabel .. "'.\n" ..
                 "УСІ ДАНІ НА ЖОРСТКОМУ ДИСКУ БУДУТЬ ВИДАЛЕНІ!\n\n" ..
                 "Ви впевнені, що хочете продовжити? (yes/no)")
    local input = io.read()
    if string.lower(input) ~= "yes" then
        printMessage("Встановлення скасовано користувачем.")
        computer.beep()
        os.sleep(2)
        computer.shutdown()
    end

    printMessage("Очищую жорсткий диск '" .. hddLabel .. "'...")
    -- Видаляємо всі файли та папки в корені диска
    local oldPath = filesystem.path() -- Зберігаємо поточний шлях
    local successCdRoot, errCdRoot = pcall(filesystem.changeDirectory, filesystem, "/", hddAddress)
    if not successCdRoot then
        printMessage("Помилка: Не вдалося перейти до кореня диска для очищення: " .. tostring(errCdRoot))
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end

    local successFormat, errFormat = deleteDirectoryRecursive("/") -- Видаляємо все рекурсивно
    if not successFormat then
        printMessage("Помилка очищення диска: " .. tostring(errFormat) .. ". Перезавантаження.")
        -- Спроба повернутися до попередньої директорії або до кореня перед вимкненням
        pcall(filesystem.changeDirectory, filesystem, oldPath)
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end
    printMessage("Очищення завершено. Жорсткий диск готовий.")
    
    -- Повертаємося до попередньої директорії або до кореня
    pcall(filesystem.changeDirectory, filesystem, oldPath)

    waitForKey()

    -- Створюємо основну директорію для Glass OS на HDD
    printMessage("Створюю директорію встановлення: " .. TARGET_HDD_DIR)
    local created, createErr = pcall(filesystem.makeDirectory, filesystem, TARGET_HDD_DIR, hddAddress)
    if not created then
        printMessage("Помилка: Не вдалося створити директорію встановлення: " .. tostring(createErr))
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end

    -- Список файлів для завантаження (оновлений відповідно до Glass-OS)
    local FILES_TO_DOWNLOAD = {
        "boot.lua", -- Змінено з main.lua на boot.lua для завантажувача
        "system/core.lua",
        "system/gui.lua",
        "system/shell.lua",
        "lib/colors.lua", 
        "lib/drawing.lua",
        "lib/utils.lua",   
        "gui_elements/window.lua", 
        "installer.lua", -- Включаємо сам інсталятор для оновлення
    }

    printMessage("Копіюю файли Glass OS на жорсткий диск...")
    for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
        local fullUrl = BASE_URL .. fileRelativePath
        local localPath = filesystem.concat(TARGET_HDD_DIR, fileRelativePath) -- Повний шлях для запису
        local successDownload, errorDownload = pcall(downloadFile, fullUrl, localPath, hddAddress)
        if not successDownload then
            printMessage("Помилка завантаження " .. fileRelativePath .. ": " .. tostring(errorDownload))
            computer.beep()
            os.sleep(5)
            computer.shutdown()
        end
    end

    printMessage("Копіювання файлів Glass OS завершено.")
    waitForKey()

    printMessage("\n[ВСТАНОВЛЕННЯ ЗАВЕРШЕНО]: Glass OS успішно встановлено на жорсткий диск.")
    print("Щоб запустити Glass OS, перезавантажте комп'ютер і виконайте команду:")
    print("lua " .. TARGET_HDD_DIR .. "/boot.lua")
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