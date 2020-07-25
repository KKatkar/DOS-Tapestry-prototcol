defmodule Tapestry do
  use GenServer

  def tapestryBegin(numNodes, numReqs) do
    {:ok, _} = GenServer.start_link(__MODULE__, :ok, name: {:global, :Parent})
    nodeRange = 1..numNodes
    hashId_list = generateIds(nodeRange)
    #IO.inspect hashId_list
    hashPid_map = generatePid(hashId_list)
    #----Here we are done mapping Pids to Hash id list
    #IO.inspect(hashPid_map)

    buildNetwork(hashPid_map,hashId_list, numReqs)

    GenServer.cast({:global, :Parent},{:tapestryUpdate, hashPid_map, numNodes, numReqs})

    forwardInfo(Map.keys(hashPid_map), hashPid_map)

  end
#------------------------------Generate SHA256 Hash ids for Tapestry------------------------------
  def generateIds(nRange) do
    hashIds=Enum.map(nRange, fn (id) -> (
                {_, hashid} = :crypto.hash(:sha256,"#{id}") |> Base.encode16() |> String.split_at(-8)
                hashid
            )end)
    hashIds
  end
#------------------Hash Id into Pid-----------------
  def generatePid(hashId_list) do
      hashid_pid_map=Enum.reduce(hashId_list, %{}, fn(hashid, hashid_pid_map ) -> (
          {pid,hashid}=Server.start(hashid)
          hashid_pid_map = Map.put(hashid_pid_map,hashid,pid)
          hashid_pid_map
      )end)
      hashid_pid_map
  end

#-------------------------------init for tapestryBegin-------------------
  def init(:ok) do
      {:ok,%{}}
  end
#------------------------------------------------------------------------

#--------------------------Network building------------------------------
  def buildNetwork(hashPid_map, hashId_list, numReqs) do
    [rows , columns] = [8, 16]

    Enum.each(hashId_list, fn(hashId) ->(join(hashId_list, hashId, hashPid_map, rows, columns, numReqs))end)

  end

  def join(hashId_list, hashId, hashPid_map, rows, columns, numReqs) do
    routingTable = computeRoutingTable(hashPid_map, hashId_list, hashId)
    GenServer.cast(hashPid_map[hashId],{:updateNode,routingTable,numReqs,rows, columns})

  end

#-------------------------routing logic---------------------
  def computeRoutingTable(hashPid_map,hashId_list,hashId) do

      routing_table=Enum.reduce(hashId_list, %{}, fn( entry ,acc_routing_table) -> (
          cond do
              (String.equivalent?(entry,hashId) == false) ->
                  longest_prefix_count = longest_prefix_match(entry,hashId,0,0)
                  acc_routing_table=Map.merge(acc_routing_table ,set_routing_table_entry(entry, longest_prefix_count, hashPid_map, acc_routing_table, hashId))
                  acc_routing_table
              true ->
                  acc_routing_table
          end
      ) end)
      #IO.inspect routing_table
      routing_table

  end

#------------------------forwarding data--------------------------

  def forwardInfo(node_list, hashId_map) do
      #IO.inspect node_list
      Enum.each(node_list, fn(x) -> (
          pId = hashId_map[x]
          GenServer.cast(pId,{:getInfo, 0, x, node_list})
          ) end)
          #IO.puts "Ending forwarding"
    end

#-----------------------longest prefix match---------------
  def longest_prefix_match(key,hash_id,start_value,longest_prefix_count) do

      longest_prefix_count = cond do
          (String.at(key,start_value) == String.at(hash_id,start_value)) ->
              longest_prefix_match(key,hash_id,start_value+1,longest_prefix_count+1)
            true ->
              longest_prefix_count
          end
      longest_prefix_count
  end
#----------------------------Routing table entry-------------------
  def set_routing_table_entry(entry, longest_prefix_count, hashid_pid_map, routing_table, hashid) do
      numRow = longest_prefix_count
      numCol = elem(Integer.parse(String.at(entry, longest_prefix_count),16),0)
      routing_table_updated = cond do
          routing_table[numRow][numCol] == nil ->
              rowMap = cond do
                  routing_table[numRow] == nil ->
                      %{}
                      true ->
                        routing_table[numRow]
                      end
            # "Rowmap #{rowMap}"
              entry_tup={entry,hashid_pid_map[entry]}
            # "entry_tup #{entry_tup}"
              rowMap = Map.put(rowMap, numCol, entry_tup)
              routing_table = Map.put(routing_table, numRow, rowMap)
              routing_table
              #true ->
              #  routing_table
              #end
        #------------------------------------
          routing_table[numRow][numCol] != nil ->
          if abs(String.to_integer(hashid, 16) - String.to_integer(entry,16)) < abs(String.to_integer(routing_table[numRow][numCol] |> Tuple.to_list |> Enum.at(0),16) - String.to_integer(hashid,16)) do
          Kernel.put_in(routing_table, [numRow, numCol], {entry, hashid_pid_map[entry]})
        else
          routing_table
        end
      end

    #IO.inspect "The updated routing table #{inspect routing_table_updated}"
      routing_table_updated
    end
    #----------------------------Update network------------------------------------------

      def handle_cast({:tapestryUpdate, hashPid_map, numNodes, numReqs}, state) do
          # IO.puts "inside update pastry"
          #IO.inspect "node map : #{inspect node_map}"
          {_, map} = Map.get_and_update(state,:node_map, fn currentVal -> {currentVal, hashPid_map} end)
          # IO.puts "done node map"
          # IO.inspect hashPid_map
          {_, currentNumNode} = Map.get_and_update(state, :numNode, fn currentVal ->{currentVal, numNodes} end)
          {_, hopCount} = Map.get_and_update(state, :hopCount, fn currentVal -> {currentVal, 0} end)
          {_, numReqs} = Map.get_and_update(state, :numReq, fn currentVal -> {currentVal, numReqs} end)
          {_, receivedReqs} = Map.get_and_update(state, :requestsReceived, fn currentVal -> {currentVal, 0} end)

          #IO.inspect " Reqrcvd: #{inspect requestsReceived}"
          state = Map.merge(state, map)
          state = Map.merge(state, currentNumNode)
          state = Map.merge(state, hopCount)
          state = Map.merge(state, numReqs)
          state = Map.merge(state, receivedReqs)
          {:noreply, state}
        end
#----------------------------------------------------------------
    def handle_cast({:delivered, hopCount}, state) do
         #IO.inspect hopCount
        {_, receivedReqs} = Map.get_and_update(state, :requestsReceived, fn currentVal -> {currentVal, currentVal + 1} end)
        state = Map.merge(state, receivedReqs)
        {_, hopCount} = Map.get_and_update(state, :hopCount, fn currentVal -> {currentVal, Kernel.max(currentVal,hopCount)} end)
        state = Map.merge(state, hopCount)

        mapReq = state[:numReq] * state[:numNode]
        if(state[:requestsReceived] >= (mapReq-1)) do
            hopMax = state[:hopCount]
            IO.puts "Max hop count = #{hopMax}"
            Process.exit(self(), :kill)
        end

        {:noreply, state}
    end

end
