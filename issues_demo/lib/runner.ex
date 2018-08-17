defmodule Demo.Runner do
  @moduledoc """
  Documentation for IssuesDemo.
  """
  alias Demo.{FileDownloader, FileDownloaderPoison, DownloadServer}
  require Logger

  @sample_url "https://s3-ap-southeast-2.amazonaws.com/dubber-andre/PANO0001.DNG"
#  @sample_url "https://s3-ap-southeast-2.amazonaws.com/dubber-andre-wav/sample_stereo.wav"


  def run_simple(qty \\ 100) do
    get_file_list(qty)
      |> Enum.map(fn({id, file}) ->
                    directory = DownloadServer.get_download_folder(id)
                    spawn_monitor(Demo.FileDownloaderPoison, :download_url, [{id, file}, directory, self()])
                  end)
    get_result(%{success: 0, error: 0}, qty)
  end

  def run_server(qty \\ 100) do
    :ok = :hackney_pool.start_pool(:pool1, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool2, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool3, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool4, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool5, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool6, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool7, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool8, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool9, [timeout: 200000, max_connections: 150])
    :ok = :hackney_pool.start_pool(:pool0, [timeout: 200000, max_connections: 150])
    get_file_list(qty)
    |> Enum.map(fn({id, file}) ->
      DownloadServer.download_file(file, self(), id)
    end)
    get_server_result(%{success: 0, error: 0}, qty)
  end

  def get_result(%{success: success, error: error} = result, qty) when success + error == qty, do: result

  def get_result(%{success: success, error: error} = result, qty) do
    receive do
      {:DOWN, _ref, :process, _pid, :normal} ->
        Logger.info("Got successful completion {#{inspect success + 1}, #{inspect error}}")
        get_result(%{result | success: success + 1}, qty)
      {:DOWN, _ref, :process, _pid, err} ->
        Logger.error("Got error in downloader: #{inspect err} {#{inspect success + 1}, #{inspect error}} ")
        get_result(%{result | error: error + 1}, qty)
      unknown ->
        Logger.error("Got unknown message: #{inspect unknown} {#{inspect success + 1}, #{inspect error}} ")
        get_result(%{result | error: error + 1}, qty)
    end

  end

  def get_server_result(%{success: success, error: error} = result, qty) when success + error == qty, do: result

  def get_server_result(%{success: success, error: error} = result, qty) do
    receive do
      {:success, _key} -> get_server_result(%{result | success: success + 1}, qty)
      {:error, _key} -> get_server_result(%{result | error: error + 1}, qty)
      unknown ->
        Logger.error("Got unknown message: #{inspect unknown} {#{inspect success}, #{inspect error}} ")
        get_server_result(%{result | error: error + 1}, qty)
    end

  end

  def get_file_list(qty) do
    1..qty
      |> Enum.map(fn(i) -> {Integer.to_string(i), @sample_url} end)
  end

end
