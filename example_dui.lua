--[[
    Example: running a DUI on prop_modern_phone and using it with the mouse.
    Copy this into your own resource (requires ox_lib). It is not loaded by this resource.

    Screen: 1080 x 2340 (9:19.5), texture dictionary "prop_modern_phone", texture "phone_screen".
    With no DUI attached the screen is black (off).
    Build your page for that size: html, body { width: 1080px; height: 2340px; overflow: hidden; }

    local Phone = require 'example_dui'
    local phone = Phone:new(GetEntityCoords(cache.ped) + vec3(0.0, 0.5, 0.0), vec3(0.0, 0.0, 0.0))
    phone:focus()   -- ESC or Backspace to leave
    phone:destroy()
]]

local DEBUG = false

local DUI_WIDTH, DUI_HEIGHT = 1080, 2340

--- @class PhoneDui
local PhoneDui = lib.class("PhoneDui")

function PhoneDui:constructor(coords, rot)
    self.cam = nil
    self.dui = nil
    self.object = nil

    ---@diagnostic disable-next-line: assign-type-mismatch
    self.model = `prop_modern_phone`

    self.txd = "prop_modern_phone"
    self.txt = "phone_screen"
    self.screenOffsets = self:getScreenOffsets()
    self.coords = coords
    self.rot = rot
    self.focused = false
    self:createObject()
end

function PhoneDui:createObject()
    self.dui = lib.dui:new({
        url = ("nui://%s/dui/build/index.html"):format(GetCurrentResourceName()),
        width = DUI_WIDTH,
        height = DUI_HEIGHT,
        debug = DEBUG
    })

    lib.requestModel(self.model)
    self.object = CreateObjectNoOffset(self.model, self.coords.x, self.coords.y, self.coords.z, false, false, false)
    SetModelAsNoLongerNeeded(self.model)

    SetEntityRotation(self.object, self.rot.x, self.rot.y, self.rot.z, 2, true)
    FreezeEntityPosition(self.object, true)

    AddReplaceTexture(self.txd, self.txt, self.dui.dictName, self.dui.txtName)
end

-- Exact corners of the screen glass in model space (front face is -Y, up is +Z).
function PhoneDui:getScreenOffsets()
    local halfWidth, halfHeight, front = 0.0331, 0.0717, -0.0037

    return {
        topLeft     = vec3(-halfWidth, front, halfHeight),
        topRight    = vec3(halfWidth, front, halfHeight),
        bottomLeft  = vec3(-halfWidth, front, -halfHeight),
        bottomRight = vec3(halfWidth, front, -halfHeight),
    }
end

function PhoneDui:getCursorPos()
    local screenX, screenY = GetActiveScreenResolution()
    local cursorX, cursorY = GetNuiCursorPosition()
    local cursorPos = vec2(cursorX / screenX, cursorY / screenY)

    local corners = {}
    for coordName, off in pairs(self.screenOffsets) do
        local offPos = GetOffsetFromEntityInWorldCoords(self.object, off.x, off.y, off.z)
        local _, x, y = GetScreenCoordFromWorldCoord(offPos.x, offPos.y, offPos.z)
        corners[coordName] = vec2(x, y)
    end

    local u, v = self:screenToTextureCoords(
        cursorPos,
        corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft
    )

    return math.floor(u * DUI_WIDTH + 0.5), math.floor(v * DUI_HEIGHT + 0.5)
end

function PhoneDui:screenToTextureCoords(point, topLeft, topRight, bottomRight, bottomLeft)
    local x, y = point.x, point.y
    local s, t = 0.5, 0.5

    for _ = 1, 10 do
        local px = (1 - s) * (1 - t) * topLeft.x + s * (1 - t) * topRight.x + s * t * bottomRight.x +
            (1 - s) * t * bottomLeft.x
        local py = (1 - s) * (1 - t) * topLeft.y + s * (1 - t) * topRight.y + s * t * bottomRight.y +
            (1 - s) * t * bottomLeft.y

        local dx = x - px
        local dy = y - py

        if math.abs(dx) < 0.0001 and math.abs(dy) < 0.0001 then
            break
        end

        local dpx_ds = (1 - t) * (topRight.x - topLeft.x) + t * (bottomRight.x - bottomLeft.x)
        local dpx_dt = (1 - s) * (bottomLeft.x - topLeft.x) + s * (bottomRight.x - topRight.x)
        local dpy_ds = (1 - t) * (topRight.y - topLeft.y) + t * (bottomRight.y - bottomLeft.y)
        local dpy_dt = (1 - s) * (bottomLeft.y - topLeft.y) + s * (bottomRight.y - topRight.y)

        local det = dpx_ds * dpy_dt - dpx_dt * dpy_ds
        if math.abs(det) < 1e-8 then
            s = s + dx * 0.1
            t = t + dy * 0.1
        else
            s = s + (dpy_dt * dx - dpx_dt * dy) / det
            t = t + (dpx_ds * dy - dpy_ds * dx) / det
        end

        s = math.max(0, math.min(1, s))
        t = math.max(0, math.min(1, t))
    end

    return s, t
end

function PhoneDui:controlLoop()
    local lastCursorX, lastCursorY = 0, 0

    EnterCursorMode()

    while self.dui and DoesEntityExist(self.object) and self.focused do
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true) -- keep chat usable
        EnableControlAction(0, 249, true) -- keep push-to-talk usable

        -- While chat or another UI has focus, don't click through it.
        if not IsNuiFocused() then
            local duiX, duiY = self:getCursorPos()

            if duiX ~= lastCursorX or duiY ~= lastCursorY then
                lastCursorX, lastCursorY = duiX, duiY
                SendDuiMouseMove(self.dui.duiObject, duiX, duiY)
            end

            if IsDisabledControlJustPressed(0, 24) then SendDuiMouseDown(self.dui.duiObject, "left") end
            if IsDisabledControlJustReleased(0, 24) then SendDuiMouseUp(self.dui.duiObject, "left") end
            if IsDisabledControlJustPressed(0, 14) then SendDuiMouseWheel(self.dui.duiObject, -120, 0) end
            if IsDisabledControlJustPressed(0, 15) then SendDuiMouseWheel(self.dui.duiObject, 120, 0) end

            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177) then
                self:clearFocus()
            end
        end

        if DEBUG then self:debug() end

        Wait(0)
    end

    LeaveCursorMode()
end

function PhoneDui:createCamera()
    if self.cam then return end

    self.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    local camPos = GetOffsetFromEntityInWorldCoords(self.object, 0.0, -0.2, 0.0)
    SetCamCoord(self.cam, camPos.x, camPos.y, camPos.z)
    PointCamAtEntity(self.cam, self.object, 0.0, 0.0, 0.0, true)
    SetCamFov(self.cam, 45.0)
    SetCamActive(self.cam, true)
    RenderScriptCams(true, true, 500, true, true)
    SetFocusEntity(self.object)
end

function PhoneDui:focus()
    if self.focused then return end
    self.focused = true

    self:createCamera()
    CreateThread(function()
        self:controlLoop()
    end)
end

function PhoneDui:clearFocus()
    self.focused = false

    if self.cam and DoesCamExist(self.cam) then
        SetCamActive(self.cam, false)
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(self.cam, false)
        ClearFocus()
        self.cam = nil
    end
end

function PhoneDui:destroy()
    self:clearFocus()

    if DoesEntityExist(self.object) then
        DeleteEntity(self.object)
        self.object = nil
    end

    if self.dui then
        RemoveReplaceTexture(self.txd, self.txt)
        self.dui:remove()
        self.dui = nil
    end
end

-- Draws the four screen corners; they should sit exactly on the edges of the glass.
function PhoneDui:debug()
    if not DoesEntityExist(self.object) then return end

    local colours = {
        topLeft = { 255, 0, 0 },
        topRight = { 0, 255, 0 },
        bottomLeft = { 0, 0, 255 },
        bottomRight = { 255, 255, 0 },
    }

    for coordName, off in pairs(self.screenOffsets) do
        local worldPos = GetOffsetFromEntityInWorldCoords(self.object, off.x, off.y, off.z)
        local _, x, y = GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
        local c = colours[coordName]
        DrawRect(x, y, 0.005, 0.005, c[1], c[2], c[3], 255)
    end
end

return PhoneDui
