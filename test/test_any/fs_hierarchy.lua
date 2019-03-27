require "iuplua"
local log = log and log(...) or print
local iupcontrols   = import_package "ant.iupcontrols"
local tree = iupcontrols.tree
local icon = iupcontrols.icon
-- local fs_dir_tree = require "fs_dir_tree"
local pm = require "antpm"

local fs = require "filesystem"
local fs_hub = require "fs_hierarchy_hub"


local fs_hierarchy = {}

function fs_hierarchy:_build()
    self.package_list = iup.list{
        "[Empty]";
        DROPDOWN="YES",
        EXPAND = "HORIZONTAL",
        VALUE = 1,
        -- AUTOHIDE = "YES",
        VISIBLEITEMS = 10,
        

    }
    self.dir_tree = tree.new {
        HIDEBUTTONS ="YES",
        HIDELINES   ="YES",
        IMAGELEAF = "IMGCOLLAPSED",
    }
    
    self.file_list = iup.list{
        "[Empty]";
        -- "[Empty]";
        -- DROPDOWN="YES",
        EXPAND = "YES",
        VALUE = 1,
        AUTOHIDE = "YES",
        SCROLLBAR = "YES",
        MULTIPLE = "YES",
        SHOWIMAGE="Yes",
    }

    self.view = iup.frame {
        iup.vbox {
            -- iup.label { title = "hierarchy",EXPAND = "HORIZONTAL" },
            iup.hbox{
                iup.label {
                    TITLE = "Package:",
                    PADDING = "1x1"
                },
                self.package_list,
            },
            iup.flatseparator {
                ORIENTATION  = "HORIZONTAL",
                BARSIZE = "5"
            },
            iup.split {
                self.dir_tree.view,
                iup.scrollbox{
                    self.file_list,
                },
                iup.fill {},
                ORIENTATION="HORIZONTAL",
                SHOWGRIP = "NO",
                VALUE = 300,
            },
            MARGIN = "3x3",
        },
        title = "hierarchy",
    }
    for arg_k,arg_v in pairs(self.iup_args) do
        self.view[arg_k] = arg_v
    end

end


function fs_hierarchy:get_view()
    if not self.view then
        self:_init()
    end
    return self.view
end


function fs_hierarchy:_init()
    self.cur_package_name = nil
    
    self:_build()
    self.dir_tree.view.map_cb = function()
        self:_load_package()
    end
    self.package_list.action = function( ... )
        self:_list_value_change(...)
    end
    self.dir_tree.view.executeleaf_cb = function(view,id)
        print("executeleaf_cb")

        self:set_foucs(id)
    end
    self.dir_tree.view.branchopen_cb = function(view,id)
        print("branchopen_cb")
        self:set_foucs(id)
    end
    self.dir_tree.view.branchclose_cb = function(view,id)
        print("branchclose_cb")

        self:set_foucs(id)
        return iup.IGNORE
    end
    self.file_list.valuechanged_cb = function()
        fs_hub.publish_selected(self)
    end
    self.view.k_any = function(dlg,c)
        if c == iup.K_1 then
            iup.Show(iup.ElementPropertiesDialog(self:get_view()))
        elseif c == iup.K_2 then
            iup.Show(iup.ElementPropertiesDialog(self.package_list))
        elseif c== iup.K_3 then
            iup.Show(iup.ElementPropertiesDialog(self.file_list))
        elseif c == iup.K_4 then
            iup.Show(iup.ElementPropertiesDialog(self.dir_tree.view))
        elseif c == iup.K_5 then
            local id = 0
            print(id,self.dir_tree.view["STATE"..id])
            if self.dir_tree.view["STATE"..id] == "EXPANDED" then
                self.dir_tree.view["STATE"..id] = "COLLAPSED"
            else
                self.dir_tree.view["STATE"..id] = "EXPANDED"
            end
        end

    end
end

--return {ref_path,...}
function fs_hierarchy:get_selected_res()
    local package = self.cur_package_name
    local dir_root_base = self.foucs_tb:string()
    -- print(package,dir_root_base)
    local package_path = self.root.path_obj:string()
    local dir_package_base = string.sub(dir_root_base,#package_path+2)
    if #dir_package_base > 0 then
        dir_package_base = dir_package_base.."/"
    end
    local selecteds = {}
    local value_str =self.file_list["VALUE"]
    for index = 1,#(value_str) do
        local chr = string.byte(value_str,index)
        if chr == string.byte("+") then
            local ref = {
                package = package,
                filename = fs.path(dir_package_base..self.file_list[index])
            }
            table.insert(selecteds,ref)
        end
    end
    print_a(selecteds)
    return selecteds
end

function fs_hierarchy:_load_package()
    print("_load_package")
    package_list = self.package_list
    package_list.REMOVEITEM = "ALL"
    local registereds = pm.get_registered_list(true)
    for i = 1,#registereds do
        package_list.APPENDITEM = registereds[i]
    end
    package_list.VALUE = math.min(#registereds,1)
    if #registereds > 0 then
        self:_show_package(registereds[1])
    end
end

function fs_hierarchy:_list_value_change(_,text, idx, state)
    print(text, idx, state)
    if state == 1 then
        self:_show_package(text)
    end
end

--package_name:"ant.xxx"
function fs_hierarchy:_show_package(package_name)
    local assetmgr = import_package "ant.asset"
    local assetdir = assetmgr.pkgdir(package_name)
    self.cur_package_name = package_name
    self.dir_tree:clear()
    self.foucs_tb = nil
    self.root = self.dir_tree:add_child(nil,assetdir:string(),true)
    self.root.path_obj = assetdir
    self:set_foucs(self.root.id)
end

function fs_hierarchy:set_foucs(node_id)
    local node = self.dir_tree:findchild_byid(node_id)
    if self.foucs_tb == node.path_obj then
        return
    end
    self.foucs_tb = node.path_obj
    print("self.foucs_tb",self.foucs_tb)
    local parent_node_id = self.dir_tree:parent(node_id)
    if parent_node_id ~= nil then
        local parent_node = self.dir_tree:findchild_byid(parent_node_id)
        local del_temp = {}
        for _,child in ipairs(parent_node) do
            if child ~= node then
                table.insert(del_temp,child)
            end
        end
        for _,child in ipairs(del_temp) do
            self.dir_tree:del(child)
        end
    end
    self.dir_tree:remove_child(node)
    local parent_path_obj = node.path_obj
    local childs = parent_path_obj:list_directory()
    self.file_list["REMOVEITEM"] = "ALL"
    local list_count = 0
    for child_obj in childs do
        
        -- local child_obj = parent_path_obj / file_name
        if fs.is_directory(child_obj)then
            local child = self.dir_tree:add_child(node,(child_obj:filename()):string(),true)
            for i=0, self.dir_tree.view.COUNT-1 do
                local t = self.dir_tree:findchild_byid(i)
            end
            child.path_obj = child_obj
        else
            local localpath = child_obj:localpath()
            self.file_list["APPENDITEM"] = (child_obj:filename()):string()
            list_count = list_count + 1
            local icona,w,h = icon.get_icon_ex(string.gsub(localpath:string(),"/","\\"),"small")
            self.file_list["IMAGE"..list_count] = icona

        end
    end


end


function fs_hierarchy.new(iup_args)
    local ins =  setmetatable({},{__index = fs_hierarchy})
    ins.iup_args = iup_args
    return ins
end

return fs_hierarchy