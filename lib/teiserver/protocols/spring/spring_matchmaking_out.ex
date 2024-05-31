# defmodule Teiserver.Protocols.Spring.MatchmakingOut do
#   @spec do_reply(atom(), nil | String.t() | tuple() | list()) :: String.t()
#   def do_reply(:full_queue_list, queues) when is_list(queues) do
#     names = queue_list(queues)
#     "s.matchmaking.full_queue_list #{names}\n"
#   end

#   def do_reply(:your_queue_list, queues) do
#     names = queue_list(queues)
#     "s.matchmaking.your_queue_list #{names}\n"
#   end

#   def do_reply(:queue_info, {the_queue, info}) do
#     parts =
#       [
#         the_queue.id,
#         the_queue.name,
#         info.mean_wait_time,
#         info.player_count
#       ]
#       |> Enum.join("\t")

#     "s.matchmaking.queue_info #{parts}\n"
#   end

#   def do_reply(:match_ready, queue_id) when is_integer(queue_id) do
#     "s.matchmaking.ready_check #{queue_id}\n"
#   end

#   def do_reply(:match_cancelled, queue_id) when is_integer(queue_id) do
#     ""
#   end

#   def do_reply(:dequeued, queue_id) when is_integer(queue_id) do
#     ""
#   end

#   defp queue_list(queues) do
#     queues
#     |> Enum.map(fn queue -> "#{queue.id}:#{queue.name}" end)
#     |> Enum.join("\t")
#   end
# end
