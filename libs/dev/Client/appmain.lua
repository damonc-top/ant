package.path = "../Common/?.lua;./?.lua;../?/?.lua;../?.lua;" .. package.path  --path for the app
--TODO: find a way to set this
--path for the remote script
package.remote_search_path = "../?.lua;?.lua;../?/?.lua;asset/?.lua;?/?.lua;ecs/?.lua;imputmgr/?.lua"
local lanes = require "lanes"
if lanes.configure then lanes.configure({with_timers = false, on_state_create = custom_on_state_create}) end
local linda = lanes.linda()

local pack = require "pack"
--"cat" means categories for different log
--for now we have "Script" for lua script log
--and "Bgfx" for bgfx log
--"Device" for deivce msg

--project entrance
local entrance = nil

local origin_print = print

function sendlog(cat, ...)
    linda:send("log", {cat, ...})
    --origin_print(cat, ...)
end

print = function(...)
    origin_print(...)
    sendlog("Script", ...)
end

local filemanager = require "filemanager"
local file_mgr = filemanager.new()
local winfile = require "winfile"

local lodepng = require "lodepnglua"

local bundle_home_dir = ""
local app_home_dir = ""
local g_WindowHandle
local g_Width, g_Height = 0

--overwrite the old io.open function, give it the ability to search resources from server
local origin_open = io.open

local function custom_open(filename, mode, search_local_only)
    --default we don't search local only
    search_local_only = search_local_only or false

    local file = origin_open(filename, mode)

    --file may be in the bundle
    --for now don't cache lua files
    --todo deal with loadfile condition
    local file_ext = string.sub(filename, -3)
    if file_ext and string.lower(file_ext)~="lua" then
        if not file then
            print("searching file in bundle: "..filename)
            --find out if it exist locally
            local local_path = file_mgr:GetRealPath(filename)
            if local_path then
                --check exist, mainly for camparing hash
                local file_exist = winfile.exist(filename)
                if file_exist then
                    print("bundle real path for: "..filename.." is "..local_path)
                    local_path = bundle_home_dir .. "/Documents/" ..local_path
                    file = origin_open(local_path, mode)

                    return file
                end
            end
        end
    end

    --file may be in the remote server
    if not file and not search_local_only then
        print("searching file in server: "..filename)
        --search online
        local request = {"GET", filename}
        linda:send("request", request)

        --TODO file not exist
        --wait here
        while true do
            local _, value = linda:receive(0.001, "new file")
            if value then
                print("received msg", filename)

                --put into the id_table and file_table
                file_mgr:AddFileRecord(value[1], value[2])
                print("add file recode: "..value[1] .. " and "..value[2])
                file_mgr:WriteDirStructure(bundle_home_dir.."/Documents/dir.txt")
                file_mgr:WriteFilePathData(bundle_home_dir.."/Documents/file.txt")

                print("file name", filename)
                local real_path = file_mgr:GetRealPath(value[2])
                real_path = bundle_home_dir .. "/Documents/" .. real_path
                file = origin_open(real_path, mode)

                print("server real file path: "..real_path)
                return file
            end
        end
    else
        print("use origin open: "..filename)
        return file
    end
end

io.open = custom_open

local function remote_searcher (name)
    --local full_path = name..".lua"
    --need to send the package search path
    print("remote requiring ".. name)
    local request = {"REQUIRE", name, package.remote_search_path}
    linda:send("request", request)

    while true do
        local key, value = linda:receive(0.001, "mem_data")
        if value then
            return load(value)
        end
    end
end
table.insert(package.searchers, remote_searcher)


local lsocket = require "lsocket"
lanes.register("lsocket", lsocket)

local function CreateIOThread(linda, home_dir)
    local client = require "client"
    local c = client.new("127.0.0.1", 8888, linda, home_dir)
    while true do
        c:mainloop(0.001)
        --print("io mainloop updating")
        local resp = c:pop()
        if resp then
            c:process_response(resp)
        end
    end
end

local function run(path)
    print("run file"..path)
    if entrance then
        entrance.terminate()
        entrance = nil
    end

    local real_path = file_mgr:GetRealPath(path)
    if real_path then
        real_path = bundle_home_dir .."/Documents/" .. real_path

        entrance = dofile(real_path)
        --must have this function and these variables for init
        entrance.init(g_WindowHandle, g_Width, g_Height, app_home_dir, bundle_home_dir)
    else
        --not in local, need require from distance
        --get file name
        local reverse_path = string.reverse(path)
        local slash_pos = string.find(reverse_path, "/")
        if slash_pos then
            reverse_path = string.sub(reverse_path, 1, slash_pos - 1)
        end
        reverse_path = string.reverse(reverse_path)
        --get rid of .lua
        reverse_path = string.sub(reverse_path, 1, -5)

        entrance = require(reverse_path)
        if entrance then
            entrance.init(g_WindowHandle, g_Width, g_Height, app_home_dir, bundle_home_dir)
        end
    end

end

local screenshot_cache_num = 0
local function HandleMsg()
    while true do
        local key, value = linda:receive(0.001, "new file", "run", "screenshot_req")
        if key == "new file" then
            --print("received msg", value)
            --put into the id_table and file_table
            file_mgr:AddFileRecord(value[1], value[2])

            file_mgr:WriteDirStructure(bundle_home_dir.."/Documents/dir.txt")
            file_mgr:WriteFilePathData(bundle_home_dir.."/Documents/file.txt")

        elseif key == "run" then
            run(value)
        elseif key == "screenshot_req" then
            --[[
            if bgfx_init then

                bgfx.request_screenshot()
                screenshot_cache_num = screenshot_cache_num + 1
                print("request screenshot: ".. value[2].." num: "..screenshot_cache_num)
            end
            --]]
        else
            break
        end
    end
end

local function HandleCacheScreenShot()
    --if screenshot_cache_num
    --for i = 1, screenshot_cache_num do
    if screenshot_cache_num > 0 then
        --todo handle screenshot
        --[[
        local name, width, height, pitch, data = bgfx.get_screenshot()
        if name then
            --print(type(name), type(pitch), type(data))
            --print("screenshot name is "..name)
            local size =#data
            --print("screenshot size is "..size)

            screenshot_cache_num = screenshot_cache_num - 1

            --compress to png format
            --default is bgra format
            local data_string = lodepng.encode_png(data, width, height);
            print("screenshot encode size ",#data_string)
            linda:send("screenshot", {name, data_string})
            --linda:send("screenshot", {name, size, width, height, pitch, data})
        end
        --]]
    end
    --end
end

local function init_lua_search_path(app_dir)

    package.path = package.path .. ";" .. app_dir .. "/libs/?.lua;" .. app_dir .. "/libs/?/?.lua;" .. app_dir .. "/libs/ecs/?.lua;"

    require "common/import"
    require "common/log"
    require "filesystem"

    print_r = require "common/print_r"

    function dprint(...) print(...) end
end

function init(window_handle, width, height, app_dir, bundle_dir)
    bundle_home_dir = bundle_dir
    app_home_dir = app_dir

    package.bundle_dir = bundle_dir
    package.app_dir = app_dir

    g_WindowHandle = window_handle
    g_Width = width
    g_Height = height


    file_mgr:ReadDirStructure(bundle_home_dir.."/Documents/dir.txt")
    file_mgr:ReadFilePathData(bundle_home_dir.."/Documents/file.txt")


    package.loaded["winfile"].loadfile = loadfile
    package.loaded["winfile"].dofile = dofile
    package.loaded["winfile"].open = io.open

    package.loaded["winfile"].personaldir = function()
        return bundle_home_dir.."/Documents"
    end
    package.loaded["winfile"].shortname = function()
        return "fileserver"
    end

    package.loaded["winfile"].exist = function(path)
        if package.loaded["winfile"].attributes(path) then
            return true
        else
            --search on the server
            local request = {"EXIST", path }
            print("request file: "..path)

            linda:send("request", request)

            --wait here
            ---[[
            while true do
                local _, value = linda:receive(0.001, "file exist")
                if value ~= nil then
                    if value then
                        print(path .. " exist")
                        return true
                    else
                        print(path .. " not exist!! " .. tostring(value))
                        return false
                    end

                    break
                end
            end
            --]]
        end

        return false
    end

    --init_lua_search_path(app_dir)

    --entrance = require "ios_main"
    --entrance.init(window_handle, width, height)
    local client_io = lanes.gen("*",{package = {path = package.path, cpath = package.cpath, preload = package.preload}}, CreateIOThread)(linda, bundle_home_dir)
end

function mainloop()
    if entrance then
        entrance.mainloop()
    end

    HandleMsg()
    HandleCacheScreenShot()
end

function terminate()
    if entrance then
        entrance.terminate()
    end

    --time to save files
    file_mgr:WriteDirStructure(bundle_home_dir.."/Documents/dir.txt")
    file_mgr:WriteFilePathData(bundle_home_dir.."/Documents/file.txt")
end

function handle_input(msg_table)
    if entrance then
        entrance.input(msg_table)
    end
end

