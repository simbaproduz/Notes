if SIMBA_InventoryReinventedPatch4212_LOADED then return end
SIMBA_InventoryReinventedPatch4212_LOADED = true

-------------------------------------------------
-- CONFIGURAÇÃO VISUAL
-------------------------------------------------
local BG = { r = 0.08, g = 0.05, b = 0.03, a = 0.85 }
local BD = { r = 0.40, g = 0.40, b = 0.40, a = 0.65 }

local SELECTED_BUTTON_SCALE = 1.5
local GRID_ICON_SCALE       = 1.6
local GRID_ICON_PADDING     = 0
local ONSCREEN_MARGIN       = 0

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function lowerName(item)
    if not item then return "" end
    local txt = ""
    if item.getDisplayName then
        txt = item:getDisplayName() or ""
    elseif item.getName then
        txt = item:getName() or ""
    end
    return string.lower(txt)
end

local function patchTooltipClass(T)
    if not T or not T.new or T.__SIMBA_TooltipPatched then return end
    local _new = T.new
    function T:new(...)
        local o = _new(self, ...)
        o.backgroundColor = { r = BG.r, g = BG.g, b = BG.b, a = BG.a }
        o.borderColor     = { r = BD.r, g = BD.g, b = BD.b, a = BD.a }
        return o
    end
    T.__SIMBA_TooltipPatched = true
end

local function firstItemFromStack(stack)
    if not stack then return nil end
    if stack.items and stack.items[1] then return stack.items[1] end
    if stack.item then return stack.item end
    return stack
end

local function isStackEquipped(stack)
    if not stack then return false end
    if stack.equipped or stack.inHotbar then return true end
    local main = firstItemFromStack(stack)
    if not main then return false end
    if main.isEquipped and main:isEquipped() then return true end
    return false
end

local function rebuildFlatGrid(pane)
    if not pane then return end

    local stacks = pane.itemslist or {}
    local pockets, equipped = {}, {}

    -- separa em bolso vs equipado
    for _, stack in ipairs(stacks) do
        local main  = firstItemFromStack(stack)
        local sort  = lowerName(main)
        local entry = { stack = stack, sortKey = sort }

        if isStackEquipped(stack) then
            table.insert(equipped, entry)
        else
            table.insert(pockets, entry)
        end
    end

    -- ordena alfabeticamente dentro de cada grupo
    local function sortByName(a, b)
        return a.sortKey < b.sortKey
    end

    table.sort(pockets,  sortByName)
    table.sort(equipped, sortByName)

    local ordered = {}
    local grid    = { firstItem = {}, xCell = {}, yCell = {} }

    local cols = 5
    local rows = 0

    -------------------------------------------------
    -- 1) ITENS DE BOLSO (EM CIMA)
    -------------------------------------------------
    for i, entry in ipairs(pockets) do
        local idx = #ordered + 1
        ordered[idx] = entry.stack

        local col = (i - 1) % cols
        if col == 0 then
            rows = rows + 1
            grid.firstItem[rows] = idx
        end

        grid.xCell[idx] = col + 1
        grid.yCell[idx] = rows
        ordered[idx].__SIMBA_gridIndex = idx
    end

    pane.__SIMBA_pocketRows = rows

    -------------------------------------------------
    -- 2) ITENS EQUIPADOS (EMBAIXO, NOVA LINHA)
    -------------------------------------------------
    for i, entry in ipairs(equipped) do
        local idx = #ordered + 1
        ordered[idx] = entry.stack

        -- recomeça a contagem de coluna pra garantir
        -- que SEMPRE começa numa nova linha
        local col = (i - 1) % cols
        if col == 0 then
            rows = rows + 1
            grid.firstItem[rows] = idx
        end

        grid.xCell[idx] = col + 1
        grid.yCell[idx] = rows
        ordered[idx].__SIMBA_gridIndex = idx
    end

    -------------------------------------------------
    -- APLICA NO PANE
    -------------------------------------------------
    pane.itemslist        = ordered
    pane.__SIMBA_flatOrder = ordered
    pane.count            = #ordered
    pane.numItems         = #ordered

    pane.collapsed        = pane.collapsed or {}
    pane.countCollapsed   = 0
    for _, stack in ipairs(ordered) do
        if stack.name then
            pane.collapsed[stack.name] = true
        end
    end

    pane.grid     = grid
    pane.numRows  = rows

    local rowH = pane.itemHgt or 32
    pane.scrollHeight = rows * rowH

    local wide = (pane.width or 0) + 5000
    pane.column2 = wide
    pane.column3 = wide
    pane.column4 = wide

    if pane.nameHeader then
        pane.nameHeader:setVisible(false)
        pane.nameHeader:setWidth(0)
    end
    if pane.typeHeader then
        pane.typeHeader:setVisible(false)
        pane.typeHeader:setWidth(0)
    end

    if pane.updateScrollbars then
        pane:updateScrollbars()
    end
end

-------------------------------------------------
-- CUSTOM RENDERING
-------------------------------------------------
local function renderFlatDetails(self, doDragged)
    if doDragged == false then
        table.wipe(self.items)
        if self.inventory and self.inventory:isDrawDirty() then
            self:refreshContainer()
        end
    end

    local stacks = self.__SIMBA_flatOrder or self.itemslist or {}
    local itemSize = self.itemHgt or 32
    local iconPx   = self.__SIMBA_iconPx or itemSize
    local padding  = math.max(0, math.floor((itemSize - iconPx) / 2))
    local edgepx   = padding + 4

    local checkDraggedItems = false
    if doDragged and self.dragging and self.dragStarted then
        self.draggedItems:update()
        checkDraggedItems = true
    end

    if not doDragged then
         self:drawRectStatic(0, 0, self.width, self.height, 0.4, 0, 0, 0)
    end

    local y = 0
    for stackIndex, stack in ipairs(stacks) do
        local items = stack.items or { stack }
        local header = items[1]
        if header then
            local gridX = (self.grid and self.grid.xCell and self.grid.xCell[stackIndex]) or (((stackIndex - 1) % 5) + 1)
            local gridY = (self.grid and self.grid.yCell and self.grid.yCell[stackIndex]) or (math.floor((stackIndex - 1) / 5) + 1)
            local baseX = (gridX - 1) * itemSize
            local baseY = (gridY - 1) * itemSize

            local count = 1
            for _, item in ipairs(items) do
                local xoff, yoff = 0, 0
                local isDragging = false
                if self.dragging and self.selected[y + 1] ~= nil and self.dragStarted then
                    xoff = self:getMouseX() - (self.draggingX or 0)
                    yoff = self:getMouseY() - (self.draggingY or 0)
                    if doDragged then
                        isDragging = true
                    end
                end

                if not doDragged then
                    self.items[y + 1] = stack
                end

                local moveX = baseX
                local moveY = baseY

                if doDragged then
                    moveX = moveX + xoff
                    moveY = moveY + yoff
                end

                if self.selected[y + 1] and not self.highlightItem then
                    if checkDraggedItems and self.draggedItems:cannotDropItem(item) then
                        -- do not highlight when item cannot be dropped
                    else
                        if not doDragged then
                            self:drawRect(moveX + 4, moveY + 3, itemSize, itemSize, 0.1, 1, 1, 1)
                            self:drawRectBorder(moveX + 3, moveY + 2, itemSize + 2, itemSize + 2, 1.0, 0.6, 0.3, 0)
                            self:drawRectBorder(moveX + 4, moveY + 3, itemSize, itemSize, 0.7, 1.0, 1.0, 1.0)
                        end
                    end
                elseif self.mouseOverOption == y + 1 and not self.highlightItem then
                    -- hover highlight intentionally removed for compact layout
                else
                    if count == 1 then
                        if (((instanceof(item, "Food") or instanceof(item, "DrainableComboItem")) and item:getHeat() ~= 1) or item:getItemHeat() ~= 1) then
                            local heat = item.getInvHeat and math.abs(item:getInvHeat()) or 0
                            if (((instanceof(item,"Food") or instanceof(item,"DrainableComboItem")) and item:getHeat() > 1) or item:getItemHeat() > 1) then
                                self:drawRect(moveX + 4, moveY + 3, itemSize, itemSize, 0.2, heat, 0.0, 0.0)
                            else
                                self:drawRect(moveX + 4, moveY + 3, itemSize, itemSize, 0.2, 0.0, 0.0, heat)
                            end
                        end
                    else
                        self:drawRect(moveX + 4, moveY + 4, itemSize, itemSize, 0.3, 0, 0, 0)
                    end
                end

                local tex = item.getTex and item:getTex() or nil
                if tex then
                    if not doDragged then
                        if self.drawTired == false then
                            ISInventoryItem.renderItemIcon(self, item, moveX + edgepx, moveY + edgepx, 1.0, 32, 32)
                        else
                            ISInventoryItem.renderItemIcon(self, item, moveX + edgepx - 6, moveY + edgepx, 0.4, 32, 32)
                            ISInventoryItem.renderItemIcon(self, item, moveX + edgepx + 6, moveY + edgepx, 0.5, 32, 32)
                        end
                    end

                    if self.joyselection and self.doController then
                        if self.joyselection < 1 then self.joyselection = 1 end
                        if self.joyselection == y + 1 then
                            self.inventoryPage.nRow = gridY
                            self:drawRect(moveX + 4, moveY + 3, itemSize, itemSize, 0.1, 1, 1, 1)
                            self:drawRectBorder(moveX + 3, moveY + 2, itemSize + 2, itemSize + 2, 1.0, 0.6, 0.3, 0)
                            self:drawRectBorder(moveX + 4, moveY + 3, itemSize, itemSize, 0.7, 1.0, 1.0, 1.0)
                        end
                    end

                    if not self.hotbar then
                        self.hotbar = getPlayerHotbar(self.player)
                    end

                    if not doDragged then
                        if not getSpecificPlayer(self.player):isEquipped(item) and self.hotbar and self.hotbar:isInHotbar(item) then
                            self:drawTexture(self.equippedInHotbar, moveX + itemSize / 2, moveY + 3, 1, 1, 1, 1)
                        end
                        if item.isBroken and item:isBroken() then
                            self:drawTexture(self.brokenItemIcon, moveX + itemSize / 2, moveY + 4, 1, 1, 1, 1)
                        end
                        if instanceof(item, "Food") and item:isFrozen() then
                            self:drawTexture(self.frozenItemIcon, moveX + itemSize - 9, moveY + 5, 1, 1, 1, 1)
                        end
                        local poisoned = false
                        if instanceof(item, "Food") then
                            if (item:isTainted() and getSandboxOptions():getOptionByName("EnableTaintedWaterText"):getValue()) or
                               getSpecificPlayer(self.player):isKnownPoison(item) or item:hasTag("ShowPoison") then
                                poisoned = true
                            end
                        end
                        if ComponentType and ComponentType.FluidContainer and item.hasComponent and item:hasComponent(ComponentType.FluidContainer) and getSandboxOptions():getOptionByName("EnableTaintedWaterText"):getValue() then
                            local fc = item.getFluidContainer and item:getFluidContainer() or nil
                            if fc and not fc:isEmpty() then
                                if fc:contains(Fluid.Bleach) or (fc:contains(Fluid.TaintedWater) and fc:getPoisonRatio() > 0.1) then
                                    poisoned = true
                                end
                            end
                        end
                        if poisoned then
                            self:drawTexture(self.poisonIcon, moveX + 9, moveY + itemSize * 0.7, 1, 1, 1, 1)
                        end
                        if (instanceof(item,"Literature") and
                                ((getSpecificPlayer(self.player):isLiteratureRead(item:getModData().literatureTitle)) or
                                (SkillBook[item:getSkillTrained()] ~= nil and item:getMaxLevelTrained() < getSpecificPlayer(self.player):getPerkLevel(SkillBook[item:getSkillTrained()].perk) + 1) or
                                (item:getNumberOfPages() > 0 and getSpecificPlayer(self.player):getAlreadyReadPages(item:getFullType()) == item:getNumberOfPages()) or
                                (item:getTeachedRecipes() and getSpecificPlayer(self.player):getKnownRecipes():containsAll(item:getTeachedRecipes())) or
                                (item:getModData().teachedRecipe and getSpecificPlayer(self.player):getKnownRecipes():contains(item:getModData().teachedRecipe()))) )
                                or (instanceof(item, "VHS") and getSpecificPlayer(self.player):getKnownMedias():contains(item:getMediaData())) then
                            self:drawTexture(self.tickMark, moveX + itemSize / 2 + 1, moveY + 2, 1, 1, 1, 1)
                        end
                        if item.isFavorite and item:isFavorite() then
                            self:drawTexture(self.favoriteStar, moveX + 7, moveY + itemSize - 14, 1, 1, 1, 1)
                        end
                    end
                end

                if count == 1 and stack.count and stack.count > 2 then
                    if not doDragged then
                        local amount = tostring((tonumber(stack.count) or 1) - 1)
                        self:drawTextRight(amount, moveX + itemSize + 2, moveY + itemSize / 2 - 1, 0, 0, 0, 1, self.font)
                        self:drawTextRight(amount, moveX + itemSize, moveY + itemSize / 2 + 1, 0, 0, 0, 1, self.font)
                        self:drawTextRight(amount, moveX + itemSize - 2, moveY + itemSize / 2 - 1, 0, 0, 0, 1, self.font)
                        self:drawTextRight(amount, moveX + itemSize, moveY + itemSize / 2 - 3, 0, 0, 0, 1, self.font)
                        self:drawTextRight(amount, moveX + itemSize, moveY + itemSize / 2 - 1, 0.8, 0.8, 0.8, 1, self.font)
                    end
                end

                if item.getJobDelta and item:getJobDelta() > 0 then
                    self:drawRect(moveX + 4, moveY + 4, itemSize, itemSize, 0.4, 0, 0, 0)
                    self:drawRect(moveX + 4, moveY + 4 + itemSize * (1 - item:getJobDelta()), itemSize, itemSize * item:getJobDelta(), 0.4, 0.4, 1.0, 0.3)
                end

                -- if stack.equipped and not isDragging then
                --    self:drawRect(0, moveY + 4, self.width, itemSize, 0.1, 0, 0, 0)
                 -- end

                if not doDragged then
                    self:drawItemDetails(item, y, 0, 0, false)
                end

                y = y + 1
                break -- stacks stay collapsed (single icon)
            end
        end
    end

    if self.draggingMarquis then
        local w = self:getMouseX() - (self.draggingMarquisX or 0)
        local h = self:getMouseY() - (self.draggingMarquisY or 0)
        self:drawRectBorder(self.draggingMarquisX or 0, self.draggingMarquisY or 0, w, h, 1, 1, 0, 0)
    end
end
-------------------------------------------------
-- TOOLTIP PATCH
-------------------------------------------------
local function SIMBA_PatchTooltips()
    if _G.ISToolTipInv_IR then patchTooltipClass(_G.ISToolTipInv_IR) end
    if _G.ISToolTipInv    then patchTooltipClass(_G.ISToolTipInv)    end
end

-------------------------------------------------
-- BIGGER ITEM ICONS
-------------------------------------------------
if ISInventoryItem and ISInventoryItem.renderItemIcon and not ISInventoryItem.__SIMBA_BigIcons then
    ISInventoryItem.__SIMBA_BigIcons = true
    local _orig = ISInventoryItem.renderItemIcon
    function ISInventoryItem.renderItemIcon(pane, item, x, y, a, w, h)
        if pane and pane.__SIMBA_iconPx then
            local px = pane.__SIMBA_iconPx
            x = x - (px - w) / 2
            y = y - (px - h) / 2
            w, h = px, px
        end
        return _orig(pane, item, x, y, a, w, h)
    end
end

-------------------------------------------------
-- GRID SCALING
-------------------------------------------------
local function SIMBA_ApplyGridScale(page)
    if not page or not page.inventoryPane then return end
    local pane = page.inventoryPane

    local scale = tonumber(GRID_ICON_SCALE) or 1.0
    scale = math.max(0.5, math.min(3.0, scale))

    local iconPx = math.max(16, math.min(128, math.floor(32 * scale + 0.5)))
    local rowH   = math.max(20, iconPx + (GRID_ICON_PADDING * 2))

    pane.__SIMBA_iconPx = iconPx
    pane.itemHgt = rowH
    pane.texScale = math.min(32, iconPx) / 32

    if pane.updateScrollbars then
        pane:updateScrollbars()
    end
end

-------------------------------------------------
-- WINDOW POSITION AND BUTTON SIZE
-------------------------------------------------
local function SIMBA_EnsureOnScreen(page)
    if not page or ONSCREEN_MARGIN <= 0 then return end
    if not page.getX or not page.getY or not page.setX or not page.setY then return end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x  = page:getX()
    local y  = page:getY()

    local m = ONSCREEN_MARGIN
    x = clamp(x, -m, sw - page.width + m)
    y = clamp(y, -m, sh - page.height + m)

    page:setX(x)
    page:setY(y)
end

local function SIMBA_FixSelectedButton(page)
    if not page or not page.backpacks then return end
    if not page.selectedButton then return end

    local baseSize = page.__SIMBA_baseBtnSize or page.buttonSize or 40
    page.__SIMBA_baseBtnSize = baseSize

    local scale = tonumber(SELECTED_BUTTON_SCALE) or 1.0
    scale = math.max(1.0, math.min(2.0, scale))

    local bigSize = math.floor(baseSize * scale + 0.5)

    for _, btn in ipairs(page.backpacks) do
        if btn and btn.setWidth and btn.setHeight then
            if btn == page.selectedButton then
                btn:setWidth(bigSize)
                btn:setHeight(bigSize)
                if btn.forceImageSize then
                    btn:forceImageSize(bigSize - 8, bigSize - 8)
                end
            else
                btn:setWidth(baseSize)
                btn:setHeight(baseSize)
                if btn.forceImageSize then
                    btn:forceImageSize(baseSize - 8, baseSize - 8)
                end
            end
        end
    end
end
-------------------------------------------------
-- PATCH INVENTORY PANE
-------------------------------------------------
local function SIMBA_PatchInventoryPaneIR()
    local Pane = _G.ISInventoryPane_IR
    if not Pane or Pane.__SIMBA_Patched then return end
    Pane.__SIMBA_Patched = true

    local orig_refreshContainer = Pane.refreshContainer
    local orig_makeItemsGrid    = Pane.makeItemsGrid
    local orig_renderdetails    = Pane.renderdetails
    local orig_doDrawItem       = Pane.doDrawItem

    function Pane:refreshContainer(...)
        if orig_refreshContainer then
            orig_refreshContainer(self, ...)
        end
        rebuildFlatGrid(self)
    end

    function Pane:makeItemsGrid(...)
        if orig_makeItemsGrid then
            orig_makeItemsGrid(self, ...)
        end
        rebuildFlatGrid(self)
    end

    function Pane:renderdetails(doDragged)
        renderFlatDetails(self, doDragged)
    end

    function Pane:doDrawItem(y, item, alt, ...)
        if not item then return y end
        local index = nil
        if item.__SIMBA_gridIndex then
            index = item.__SIMBA_gridIndex
        elseif self.__SIMBA_flatOrder then
            for i, stack in ipairs(self.__SIMBA_flatOrder) do
                if stack == item or stack == item.item then
                    index = i
                    break
                end
            end
        end
        if index then
            local row = math.floor((index - 1) / 5)
            y = row * (self.itemHgt or 32)
        end
        if orig_doDrawItem then
            return orig_doDrawItem(self, y, item, alt, ...)
        end
        return y + (self.itemHgt or 32)
    end

    function Pane:updateDynamicColumns()
        local wide = (self.width or 0) + 5000
        self.column2 = wide
        self.column3 = wide
        self.column4 = wide
        if self.nameHeader then
            self.nameHeader:setVisible(false)
            self.nameHeader:setWidth(0)
        end
        if self.typeHeader then
            self.typeHeader:setVisible(false)
            self.typeHeader:setWidth(0)
        end
    end

    local empty = function() end
    if Pane.drawCategories then Pane.drawCategories = empty end
    if Pane.drawCategoryHeader then Pane.drawCategoryHeader = empty end
    if Pane.renderCategoryDivider then Pane.renderCategoryDivider = empty end
    if Pane.prerenderCategories then Pane.prerenderCategories = empty end
end
-------------------------------------------------
-- EVENT HANDLERS
-------------------------------------------------
local function SIMBA_OnRefreshInventoryWindowContainers(page, phase)
    if not page or phase ~= "end" then return end
    SIMBA_FixSelectedButton(page)
    SIMBA_ApplyGridScale(page)
    SIMBA_EnsureOnScreen(page)
    if page.inventoryPane and page.inventoryPane.makeItemsGrid then
        page.inventoryPane:makeItemsGrid()
    end
end

-------------------------------------------------
-- BOOTSTRAP
-------------------------------------------------
local function SIMBA_InventoryReinvented_Boot()
    SIMBA_PatchTooltips()
    SIMBA_PatchInventoryPaneIR()
    if ISInventoryPage and not ISInventoryPage.__SIMBA_OnRefreshHooked then
        Events.OnRefreshInventoryWindowContainers.Add(SIMBA_OnRefreshInventoryWindowContainers)
        ISInventoryPage.__SIMBA_OnRefreshHooked = true
    end
end

Events.OnGameBoot.Add(SIMBA_InventoryReinvented_Boot)
Events.OnGameStart.Add(SIMBA_InventoryReinvented_Boot)
Events.OnLoad.Add(SIMBA_InventoryReinvented_Boot)
