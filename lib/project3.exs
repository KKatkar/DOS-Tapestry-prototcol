defmodule Proj3 do

	[args1, args2] = System.argv()
	nodes = String.to_integer(args1)
	requests = String.to_integer(args2)
	IO.puts("number of nodes: #{nodes}")
	IO.puts("number of requests: #{requests}" )
	Tapestry.tapestryBegin(nodes,requests)


	def looping() do
		looping()
	end
end

Proj3
Proj3.looping()
