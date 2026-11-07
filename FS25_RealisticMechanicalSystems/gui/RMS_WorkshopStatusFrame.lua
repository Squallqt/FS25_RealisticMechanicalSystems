-- Copyright © 2026 Squallqt. All rights reserved.

---Band telling whether the workshop takes an order
RMS_WorkshopStatusFrame = {}

local RMS_WorkshopStatusFrame_mt = Class(RMS_WorkshopStatusFrame, FrameElement)

---Creates the band
function RMS_WorkshopStatusFrame.new()
    return FrameElement.new(nil, RMS_WorkshopStatusFrame_mt)
end

---Writes the state of the workshop
function RMS_WorkshopStatusFrame:setStatus(state)
    self.statusText:setText(state.statusText)
    self.statusText:setTextColor(unpack(state.statusColor))
    self.statusGroup:invalidateLayout()
end
