-- installer.lua
-- Інсталятор для Glass OS в OpenComputers
-- Цей файл буде розміщено на GitHub разом з іншими файлами Glass OS

local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local io = require("io")

-- Налаштування репозиторію (ЗМІНІТЬ ЦІ ЗНАЧЕННЯ НА СВОЇ!)
local GITHUB_USER = "ВАШ_НІКНЕЙМ_НА_GITHUB" -- Наприклад: "MyCoolDev"
local GITHUB_REPO = "GlassOS"             -- Назва вашого репозиторію на GitHub (та, яку ви вказали вище)
local GITHUB_BRANCH = "main"              -- Зазвичай "main" або "master"

local BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
local TARGET_DIR = "/home/glassos" -- Директорія, куди буде встановлено Glass OS на комп'ютері OpenComputers

-- Список файлів, які потрібно завантажити (додавайте сюди всі нові файли та папки!)
local FILES_TO_DOWNLOAD = {
    "main.lua",
    "lib/colors.lua",
    "lib/drawing.lua",
    "lib/utils.lua",
    "gui_elements/window.lua",
    -- Якщо ви створите apps/terminal.lua, додайте його сюди:
    -- "apps/terminal.lua",
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
        error("Не вдалося завантажити " .. url .. ". Можливо, немає доступу до інтернету або файл не існує.")
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

    -- Створюємо основну директорію для Glass OS
    if not filesystem.exists(TARGET_DIR) then
        print("Створюю директорію: " .. TARGET_DIR)
        if not filesystem.makeDirectory(TARGET_DIR) then
            error("Не вдалося створити директорію: " .. TARGET_DIR)
        end
    end

    -- Переходимо в цільову директорію для зручності
    local oldPath = filesystem.path()
    filesystem.changeDirectory(TARGET_DIR)
    
    -- Завантажуємо всі файли зі списку
    for _, fileRelativePath in ipairs(FILES_TO_DOWNLOAD) do
        local fullUrl = BASE_URL .. fileRelativePath
        local localPath = fileRelativePath

        -- Перевіряємо та створюємо всі необхідні піддиректорії (наприклад, lib/, gui_elements/)
        local dirName = filesystem.directory(localPath)
        if dirName ~= "" and not filesystem.exists(dirName) then
            print("Створюю піддиректорію: " .. dirName)
            if not filesystem.makeDirectory(dirName) then
                error("Не вдалося створити піддиректорію: " .. dirName)
            end
        end

        downloadFile(fullUrl, localPath)
    end

    -- Створюємо простий скрипт для запуску Glass OS
    local runScriptPath = "/home/start_glassos.lua"
    local runScriptContent = [[
        local filesystem = require("filesystem")
        local shell = require("shell")
        if filesystem.exists("]] .. TARGET_DIR .. [[/main.lua") then
            print("Запускаю Glass OS...")
            shell.execute("lua " .. "]] .. TARGET_DIR .. [[/main.lua")
        else
            print("Помилка: Файл main.lua не знайдено за адресою ]] .. TARGET_DIR .. [[/main.lua")
            print("Будь ласка, переконайтеся, що Glass OS встановлено коректно.")
        end
    ]]
    local runFile, runError = io.open(runScriptPath, "w")
    if not runFile then
        error("Не вдалося створити скрипт запуску: " .. runError)
    end
    runFile:write(runScriptContent)
    runFile:close()
    shell.execute("chmod +x " .. runScriptPath) -- Робимо скрипт виконуваним
    print("Скрипт запуску створено: " .. runScriptPath)

    filesystem.changeDirectory(oldPath) -- Повертаємося до початкової директорії

    print("\nВстановлення Glass OS завершено!")
    print("Для запуску ОС виконайте: \z" .. runScriptPath .. "\z")
end

-- Запуск інсталятора (з обробкою помилок)
local success, errorMessage = pcall(installGlassOS)
if not success then
    print("\n[ПОМИЛКА ВСТАНОВЛЕННЯ]: " .. tostring(errorMessage))
    computer.beep()
end