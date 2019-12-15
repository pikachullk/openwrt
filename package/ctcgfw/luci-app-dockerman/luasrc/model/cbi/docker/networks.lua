--[[
LuCI - Lua Configuration Interface
Copyright 2019 lisaac <lisaac.cn@gmail.com>
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
	http://www.apache.org/licenses/LICENSE-2.0
$Id$
]]--

require "luci.util"
local uci = luci.model.uci.cursor()
local docker = require "luci.model.docker"
local dk = docker.new()
local networks
local res = dk.networks:list()
if res.code < 300 then networks = res.body else return end

local get_networks = function ()
  local data = {}

  if type(networks) ~= "table" then return nil end
  for i, v in ipairs(networks) do
    local index = v.Created .. v.Id
    data[index]={}
    data[index]["_selected"] = 0
    data[index]["_id"] = v.Id:sub(1,12)
    data[index]["_name"] = v.Name
    data[index]["_driver"] = v.Driver
    if v.Driver == "bridge" then
      data[index]["_interface"] = v.Options["com.docker.network.bridge.name"]
    elseif v.Driver == "macvlan" then
      data[index]["_interface"] = v.Options.parent
    end
    data[index]["_subnet"] = v.IPAM and v.IPAM.Config[1] and v.IPAM.Config[1].Subnet or nil
    data[index]["_gateway"] = v.IPAM and v.IPAM.Config[1] and v.IPAM.Config[1].Gateway or nil
  end
  return data
end

local network_list = get_networks()
-- m = Map("docker", translate("Docker"))
m = SimpleForm("docker", translate("Docker"))
m.tempalte = "cbi/xsimpleform"
m.submit=false
m.reset=false

network_table = m:section(Table, network_list, translate("Networks"))
network_table.nodescr=true

network_selecter = network_table:option(Flag, "_selected","")
network_id = network_table:option(DummyValue, "_id", translate("ID"))
network_selecter.disabled = 0
network_selecter.enabled = 1
network_selecter.default = 0
for k, v in pairs(network_list) do
  if v["_name"] ~= "bridge" and v["_name"] ~= "none" and v["_name"] ~= "host" then
    network_selecter:depends("_name", v["_name"])
  end
end

network_name = network_table:option(DummyValue, "_name", translate("Name"))
network_driver = network_table:option(DummyValue, "_driver", translate("Driver"))
network_interface = network_table:option(DummyValue, "_interface", translate("Interface"))
network_subnet = network_table:option(DummyValue, "_subnet", translate("Subnet"))
network_gateway = network_table:option(DummyValue, "_gateway", translate("Gateway"))

network_selecter.write = function(self, section, value)
  network_list[section]._selected = value
end

docker_status = m:section(SimpleSection)
docker_status.template="docker/apply_widget"
docker_status.err=nixio.fs.readfile(dk.options.status_path)
if docker_status then docker:clear_status() end

action = m:section(Table,{{}})
action.notitle=true
action.rowcolors=false
action.template="cbi/nullsection"
btnnew=action:option(Button, "_new")
btnnew.inputtitle= translate("New")
btnnew.template="cbi/inlinebutton"
btnnew.notitle=true
btnnew.inputstyle = "add"
btnnew.forcewrite = true
btnnew.write = function(self, section)
  luci.http.redirect(luci.dispatcher.build_url("admin/docker/newnetwork"))
end
btnremove = action:option(Button, "_remove")
btnremove.inputtitle= translate("Remove")
btnremove.template="cbi/inlinebutton"
btnremove.inputstyle = "remove"
btnremove.forcewrite = true
btnremove.write = function(self, section)
  local network_selected = {}
  -- 遍历table中sectionid
  local network_table_sids = network_table:cfgsections()
  for _, network_table_sid in ipairs(network_table_sids) do
    -- 得到选中项的名字
    if network_list[network_table_sid]._selected == 1 then
      network_selected[#network_selected+1] = network_name:cfgvalue(network_table_sid)
    end
  end
  if next(network_selected) ~= nil then
    local success = true
    docker:clear_status()
    for _,net in ipairs(network_selected) do
      docker:append_status("Networks: " .. "remove" .. " " .. net .. "...")
      local res = dk.networks["remove"](dk, net)
      if res and res.code >= 300 then
        docker:append_status("fail code:" .. res.code.." ".. (res.body.message and res.body.message or res.message).. "<br>")
        success = false
      else
        docker:append_status("done<br>")
      end
    end
    if success then
      docker:clear_status()
    end
    luci.http.redirect(luci.dispatcher.build_url("admin/docker/networks"))
  end
end

return m