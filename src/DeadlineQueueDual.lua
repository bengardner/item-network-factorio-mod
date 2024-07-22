--[[
This provides a dual deadline queue.
One spans 1 second, then other spans 60 seconds
Probably not worth it.
]]
local DeadlineQueueDual = {}

local DeadlineQueue = require 'DeadlineQueue2'

-- fine slices
local QUEUE_FINE_SLICE_COUNT = 60
local QUEUE_FINE_SLICE_TICKS = 1

-- coarse slices
local QUEUE_COARSE_SLICE_COUNT = 60
local QUEUE_COARSE_SLICE_TICKS = 60

--[[
Add an item to the queue.
If the deadline is out of range, this adds it to the last entry.
When hit with next(), it will be requeued.
]]
function DeadlineQueueDual.queue(self, key, val, deadline)
	if not DeadlineQueue.queue_maybe(self.q_fine, key, val, deadline) then
		DeadlineQueue.queue(self.q_coarse, key, val, deadline)
	end
end

--[[
Remove a key from the queue.
]]
function DeadlineQueueDual.purge(self, key)
	DeadlineQueue.purge(self.q_fine)
	DeadlineQueue.purge(self.q_coarse)
end

--[[
Move everything that is read from q_coarse to q_fine.
Return the next q_fine item
]]
function DeadlineQueueDual.next(self)
	-- transfer stuff from q_coarse to q_fine
	while true do
		local key, val = DeadlineQueue.next_coarse(self.q_coarse)
		if not key then
			break
		end
		DeadlineQueue.queue(self.q_fine, key, val, val._deadline)
	end
	-- grab from q_fine
	return DeadlineQueue.next(self.q_fine)
end

--[[
Create a new DeadlineQueue instance.
]]
function DeadlineQueueDual.new()
	local self = {
		q_fine = DeadlineQueue.new(90, 1),
		q_coarse = DeadlineQueue.new(100, 60),
	}
	return self
end

return DeadlineQueueDual
