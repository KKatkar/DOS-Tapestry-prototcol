defmodule Server do
  use GenServer

#--------------------Entering from Tapestry.tapestryBegin---------------------------
  def start(hashId) do
    {:ok,pid} = GenServer.start(__MODULE__,hashId)
    {pid,hashId}
  end

  def init(args) do
      {:ok,%{:node_id => args}}
  end
#-----------------------------------------------------------------------------------

  def handle_cast({:updateNode,routingTable,numReqs,rows, columns},state) do
    {_,routing_Table}=Map.get_and_update(state,:routing_table, fn current_value -> {current_value,routingTable} end)
    {_,num_Reqs}=Map.get_and_update(state,:num_req, fn current_value -> {current_value,numReqs} end)
    # {_,hop_count}=Map.get_and_update(state,:hop_count, fn current_value -> {current_value,0} end)
    {_,num_rows}=Map.get_and_update(state,:num_rows, fn current_value -> {current_value,rows} end)
    {_,num_columns}=Map.get_and_update(state,:num_cols, fn current_value -> {current_value,columns} end)

    state=Map.merge(state, routing_Table)
    state=Map.merge(state, num_Reqs)
    # state=Map.merge(state, hop_count)
    state=Map.merge(state, num_rows)
    state=Map.merge(state, num_columns)

    {:noreply,state}

  end


#------------------------------------handle information---------------------

  def handle_cast({:getInfo, currentCount, hashId, nodeList}, state) do
      if(currentCount < state[:num_req]) do
          key = Enum.random(nodeList)
          # nodeList = nodeList -- [key]
          pathTillNow = []
          currentCount= cond do
              (String.equivalent?(key, hashId) == false) ->
                  GenServer.cast(self(), {:route, hashId, key, 0, pathTillNow})
                  currentCount = currentCount + 1
                  currentCount

                  true ->
                    currentCount
                  end
                  GenServer.cast(self(), {:getInfo, currentCount, hashId, nodeList})
                end
                {:noreply, state}
  end

#----------------------- routing---------------------------
  def handle_cast({:route, source, destination, hopCount, pathTillNow}, state) do
    cond do

        String.equivalent?(source, destination) == true ->
          GenServer.cast({:global, :Parent}, {:delivered,hopCount})
    true ->
    longest_prefix_count = Tapestry.longest_prefix_match(source, destination,0,0)
    #
    routing_table = state[:routing_table]
    {routing_table_entry,entry_pid} = get_routing_table_entry(destination, longest_prefix_count, routing_table)
    if(routing_table_entry != nil) do
        # IO.puts "Source #{inspect source} Destination #{destination} inside routing table : #{inspect routing_table} entry: #{inspect routing_table_entry}"
        # IO.puts("Path till now #{inspect pathTillNow}")
        pathTillNow = [routing_table_entry] ++ pathTillNow
        # IO.puts("Path till now #{inspect pathTillNow}")
        # IO.puts "Routing table"
        GenServer.cast(entry_pid, {:route, routing_table_entry, destination, hopCount + 1, pathTillNow})
    else
      a_d = diffKeyElement(source, destination)
      route_list=
      Enum.reduce(routing_table, [] , fn({_r, row} , acc_route_list) ->(
          row_list=
          Enum.reduce(row, [], fn({_c ,{hashid, pid}},acc_row_list) -> (
              acc_row_list = [{hashid, pid}] ++ acc_row_list
              acc_row_list
          )end)

          acc_route_list=row_list ++ acc_route_list
          acc_route_list
      )end)

      isFound = Enum.reduce(route_list, false , fn({x,pid},acc_isFound) -> (
          t_len = Tapestry.longest_prefix_match(x, destination,0,0)
          acc_isFound= cond do
              (t_len >= longest_prefix_count) ->

                  t_d = diffKeyElement(x, destination)
                  acc_isFound=cond do
                      (acc_isFound == false && t_d < a_d) ->
                          acc_isFound = true

                          pathTillNow = [source] ++ pathTillNow
                          # IO.puts("Inside the combined case")
                          # IO.puts("combined case Source #{inspect source} Destination #{inspect destination} Path till now #{inspect pathTillNow} next hop #{inspect x}")
                          # IO.puts "Inside the combined case #{inspect pathTillNow}"
                          # IO.puts "Combined case"
                          GenServer.cast(pid, {:route, x, destination, hopCount + 1, pathTillNow})
                          acc_isFound

                      true ->
                          acc_isFound
                      end
                  acc_isFound

              true ->
                  acc_isFound
          end

          acc_isFound
      )end)


      #not expecting this to happen at all.
      if(isFound == false) do

          GenServer.cast({:global, :Parent}, {:delivered,hopCount})
      end
    end
    end
    {:noreply, state}
  end

  def diffKeyElement(key, x) do
      k=elem(Integer.parse(key,16),0)
      x=elem(Integer.parse(x,16),0)
      diff=abs(k-x)
      diff
  end
#-------------------------------Access to created table entries-----------------
  def get_routing_table_entry(key, longest_prefix_count, routing_table) do
      numRow = longest_prefix_count
      #orig numCol = Integer.parse(String.at(key, longest_prefix_count))
      numCol = elem(Integer.parse(String.at(key, longest_prefix_count),16),0)
      result = cond do
          routing_table[numRow][numCol] != nil ->
              routing_table[numRow][numCol]
          true ->
              {nil,nil}
      end
      result
  end



end
