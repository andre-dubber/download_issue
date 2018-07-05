defmodule IssuesDemo do
  @moduledoc """
  Documentation for IssuesDemo.
  """

  require Logger

  @sample_url "https://s3-ap-southeast-2.amazonaws.com/dubber-andre-wav/sample_stereo.wav"

  def run do
    get_file_list()
      |> Enum.map(fn({id, file}) ->
                    directory = Temp.mkdir!(%{basedir: "./",
                                              prefix: "temp_files_#{id}_",
                                              suffix: ""})

                    spawn_monitor(FileDownloader, :download_url, [{id, file}, directory])
                  end)
    get_result(%{success: 0, error: 0})
  end

  def get_result(%{success: success, error: error} = result) when success + error == 100, do: result

  def get_result(%{success: success, error: error} = result) do
    receive do
      {:DOWN, _ref, :process, _pid, :normal} ->
        Logger.info("Got successful completion {#{inspect success + 1}, #{inspect error}}")
        get_result(%{result | success: success + 1})
      {:DOWN, _ref, :process, _pid, err} ->
        Logger.error("Got error in downloader: #{inspect err} {#{inspect success + 1}, #{inspect error}} ")
        get_result(%{result | error: error + 1})
      unknown ->
        Logger.error("Got unknown message: #{inspect unknown} {#{inspect success + 1}, #{inspect error}} ")
        get_result(%{result | error: error + 1})
    end

  end

  def get_file_list do
    1..100
      |> Enum.map(fn(i) -> {Integer.to_string(i), @sample_url} end)
  end

end
