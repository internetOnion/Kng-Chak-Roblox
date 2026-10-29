--!strict
--[[
	Signal: a tiny event that code can Connect to and Fire.

	    local hit = Signal.new()
	    local connection = hit:Connect(function(damage) print(damage) end)
	    hit:Fire(8)
	    connection:Disconnect()

	Handlers run in the order they connected, each in its own thread (task.spawn),
	so a handler that errors or yields never blocks the code that fired the signal
	or the handlers after it.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

type Entry = {
	connection: Connection,
	handler: (...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local entries: { Entry } = {}

	local function disconnect(connection: Connection)
		connection.Connected = false
		for i, entry in entries do
			if entry.connection == connection then
				table.remove(entries, i)
				return
			end
		end
	end

	local signal = {}

	function signal.Connect(_: Signal, handler: (...any) -> ()): Connection
		local connection: Connection = { Connected = true, Disconnect = disconnect }
		table.insert(entries, { connection = connection, handler = handler })
		return connection
	end

	function signal.Once(self: Signal, handler: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function signal.Wait(self: Signal): ...any
		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal.Fire(_: Signal, ...: any)
		-- Iterate a copy, so handlers can connect or disconnect while we fire.
		for _, entry in table.clone(entries) do
			if entry.connection.Connected then
				task.spawn(entry.handler, ...)
			end
		end
	end

	function signal.DisconnectAll(_: Signal)
		for _, entry in entries do
			entry.connection.Connected = false
		end
		table.clear(entries)
	end

	return (signal :: any) :: Signal
end

return Signal
