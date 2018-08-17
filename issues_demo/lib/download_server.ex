defmodule Demo.DownloadServer do
  @moduledoc false

  require Logger
  require Integer
  alias Demo.FileDownloaderPoison

  use GenServer

  def start_link do
    Logger.info("Starting DownloadServer")
    GenServer.start_link(__MODULE__, [], name: :download_server)
  end

  def init(_state) do
    {:ok, []}
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:download_file, url, stream_to_pid, job_key}, _from, state) do
    {download_pid, monitor, directory, new_state} =
      process_download_file(url, job_key, state, stream_to_pid)
    Logger.info("DownloadServer: Downloading file for #{job_key}")
    {:reply, {download_pid, monitor, directory}, new_state}
  end

  def handle_info({_from, :downloaded_chunk, {:ok, directory, chunk_no}}, state) do
    process_downloaded_chunk(directory, chunk_no, state)
    {:noreply, state}
  end

  def handle_info({_from, :download_complete, {:ok, key, total_chunks, time}}, state) do
    new_state = process_download_complete(key, total_chunks, state, time)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, error}, state) do
    new_state = download_failed(pid, state, error)
    {:noreply, new_state}
  end

  def get_state do
    GenServer.call(:download_server, :get_state)
  end


  def download_failed(pid, state, error) do
    Enum.filter(state,
      fn (%{} = m) ->
        if m.download_pid == pid do
          Logger.error("DownloadServer: Download failed with #{inspect error} for #{m.job_key} " <>
                      "remaining jobs: #{Enum.count(state) - 1}")
          send(m.stream_to_pid, {:error, m.job_key})
          false
        else
          true
        end
      end)
  end

  def download_file(url, stream_to_pid, key) do
    GenServer.call(:download_server,
      {:download_file,
        url,
        stream_to_pid,
        key})
  end

  def process_download_file(url, job_key, state, stream_to_pid) do
    Logger.info("DownloadServer: Got download_file request for #{url} key:  #{inspect job_key}")
    directory = get_download_folder(job_key)
    pool = get_pool(job_key)
    {download_pid, monitor} = spawn_monitor(FileDownloaderPoison, :download_url, [{job_key, url}, directory, self(), pool])
    new_state = state ++ [%{url: url, download_pid: download_pid, directory: directory,
      stream_to_pid: stream_to_pid, job_key: job_key}]
    {download_pid, monitor, directory, new_state}
  end

  def get_pool(job_key) do
    "pool" <> String.slice(job_key, -1..-1) |> String.to_atom
  end

  def get_download_folder(job_key) do
    Temp.mkdir!(%{basedir: "./",
      prefix: "temp_files_#{job_key}_",
      suffix: ""})

  end

  def process_download_complete(key, total_chunks, state, time) do
    Enum.filter(state,
      fn (%{} = m) ->
        if m.job_key == key do
          Logger.info("DownloadServer: Job #{m.job_key} download done " <>
                      "total chunks #{inspect total_chunks} took #{inspect time} seconds " <>
                      "remaining jobs: #{Enum.count(state) - 1}")
          send(m.stream_to_pid, {:success, m.job_key})
          false
        else
          true
        end
      end)
  end

  def process_downloaded_chunk(directory, _chunk_no, state) do
    Enum.map(state,
      fn (%{} = m) ->
        if m.directory == directory do
          nil #
        end
      end)
  end


end
