-- installer.lua
-- Інсталятор для Glass OS в OpenComputers (без прошивки BIOS)

local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local io = require("io") -- Забезпечуємо завантаження io
local event = require("event") -- Для waitForKey
local os = require("os") -- Для os.sleep

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
        -- Використовуємо pcall для безпечного виклику GPU методів, оскільки GPU може бути несправним або не ініціалізованим
        local successRes, errMsgRes = pcall(gpu.setResolution, gpu, gpu.maxResolution())
        if not successRes then
             -- Якщо не вдалося встановити максимальну роздільну здатність, спробувати щось простіше
             pcall(gpu.setResolution, gpu, 80, 25)
        end
        local maxWidth, maxHeight = gpu.getResolution()
        pcall(gpu.setBackground, gpu, 0x000000) -- Чорний фон
        pcall(gpu.setForeground, gpu, 0xFFFFFF) -- Білий текст
        pcall(gpu.fill, gpu, 1, 1, maxWidth, maxHeight, " ")
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
    local success, data = pcall(function()
        local handle = shell.open(url)
        if not handle then error("Не вдалося відкрити URL. Можливо, немає мережевого підключення або URL неправильний.") end
        local content = handle:readAll()
        handle:close()
        return content
    end)

    if not success or not data then
        error("Не вдалося завантажити " .. url .. ". Можливо, немає доступу до інтернету, файл не існує або інша проблема: " .. tostring(data))
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
    local hddAddress = nil
    local rootFsAddress = component.list("filesystem", true)() -- Отримуємо адресу кореневої файлової системи

    -- Спершу шукаємо додатковий диск (не кореневий)
    for address in component.list("filesystem") do
        local fs = component.get(address)
        if fs and fs.isFormatted and not fs.isReadOnly then
            if address ~= rootFsAddress then -- Пропускаємо диск, з якого завантажились
                hdd = fs
                hddAddress = address
                break
            end
        end
    end

    -- Якщо не знайшли додаткового диска, пропонуємо використовувати кореневий
    if not hdd then
        if rootFsAddress then
            hdd = component.get(rootFsAddress)
            hddAddress = rootFsAddress
            printMessage("Попередження: Не знайдено іншого диска для встановлення. Буде використано диск, з якого завантажено OpenOS.")
            print("УВАГА: Це призведе до ВИДАЛЕННЯ OpenOS! Переконайтеся, що це те, що ви хочете.")
            waitForKey()
        end
    end

    if not hdd then
        printMessage("Помилка: Не знайдено жодного жорсткого диска для встановлення Glass OS. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown() -- Вимкнення замість os.exit() для надійності
    end

    local hddLabel = ""
    if hdd.getLabel then -- Перевірка наявності getLabel
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
    local successFormat, errFormat = pcall(hdd.format)
    if not successFormat then
        printMessage("Помилка форматування диска: " .. tostring(errFormat) .. ". Можливо, диск захищений від запису або пошкоджений. Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
    end
    printMessage("Форматування завершено. Жорсткий диск очищено.")
    waitForKey()

    -- 3. Копіюємо файли на жорсткий диск
    printMessage("Копіюю файли Glass OS на жорсткий диск...")
    local oldPath = filesystem.path() -- Зберігаємо поточний шлях
    
    local successCopy, errCopy = pcall(function()
        -- Створюємо основну директорію для Glass OS на HDD
        if not filesystem.exists(TARGET_HDD_DIR, hddAddress) then
            local created, createErr = filesystem.makeDirectory(TARGET_HDD_DIR, hddAddress)
            if not created then
                error("Не вдалося створити директорію '" .. TARGET_HDD_DIR .. "' на HDD: " .. createErr)
            end
        end
        -- Змінюємо поточну робочу директорію для сесії інсталятора на цільову директорію на HDD
        local successCd, cdErr = filesystem.changeDirectory(TARGET_HDD_DIR, hddAddress)
        if not successCd then
            error("Не вдалося перейти в директорію '" .. TARGET_HDD_DIR .. "' на HDD: " .. cdErr)
        end

        -- Копіюємо всі файли з FILES_TO_DOWNLOAD
        for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
            local fullUrl = BASE_URL .. fileRelativePath
            local localPath = fileRelativePath -- Це відносний шлях у рамках TARGET_HDD_DIR

            local dirName = filesystem.directory(localPath)
            if dirName ~= "" then
                local currentDirSegment = ""
                -- Розбиваємо шлях на сегменти і створюємо кожен сегмент, якщо його немає
                for segment in string.gmatch(dirName, "[^/\\]+") do
                    currentDirSegment = filesystem.concat(currentDirSegment, segment)
                    -- Перевіряємо існування та створюємо піддиректорії відносно поточної директорії (що зараз TARGET_HDD_DIR)
                    if not filesystem.exists(currentDirSegment) then 
                        local created, createErr = filesystem.makeDirectory(currentDirSegment)
                        if not created then
                            error("Не вдалося створити піддиректорію '" .. currentDirSegment .. "': " .. createErr)
                        end
                    end
                end
            end
            downloadFile(fullUrl, localPath)
        end

    end)

    -- Намагаємося повернутися до попередньої директорії або до кореня, якщо oldPath недійсний
    local successReturn, errReturn = pcall(filesystem.changeDirectory, filesystem, oldPath)
    if not successReturn then
        pcall(filesystem.changeDirectory, filesystem, "/") -- Спроба повернутися до кореня, якщо не вдалося повернутися до старого шляху
    end

    if not successCopy then
        printMessage("Помилка копіювання файлів: " .. tostring(errCopy) .. ". Перезавантаження.")
        computer.beep()
        os.sleep(5)
        computer.shutdown()
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
    computer.shutdown() -- Вимкнення, якщо інсталятор впав
end