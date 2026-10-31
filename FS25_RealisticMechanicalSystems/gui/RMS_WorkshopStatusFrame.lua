-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Band telling whether the workshop takes an order
RMS_WorkshopStatusFrame = {}

local RMS_WorkshopStatusFrame_mt = Class(RMS_WorkshopStatusFrame, FrameElement)

---Creates the band
-- @return table frame
function RMS_WorkshopStatusFrame.new()
    return FrameElement.new(nil, RMS_WorkshopStatusFrame_mt)
end

---Writes the state of the workshop
-- @param table state workshop state of RMS_WorkshopDialog:refresh
function RMS_WorkshopStatusFrame:setStatus(state)
    self.statusText:setText(state.statusText)
    self.statusText:setTextColor(unpack(state.statusColor))
    self.statusGroup:invalidateLayout()
end
