defmodule Demo.FileDownloaderPoison do

  require Logger

  def download_url(params, directory, pid, pool \\ :pool1)
  def download_url({file_id, url}, directory, pid, pool) do
    IO.inspect pool
    file = File.open("#{directory}/output#{file_id}.wav", [:binary, :write])
    opts = [stream_to: self(), async: :once, hackney: [follow_redirect: true, pool: pool]]
    case HTTPoison.get!(url, [], opts) do
      %HTTPoison.AsyncResponse{id: id} ->
        async_response(url, id, %{directory: directory, chunk_no: 0, file: file,
                                  file_id: file_id, pid: pid, start: Time.utc_now})

      %HTTPoison.Error{reason: msg} ->
        Logger.error("Received error #{inspect msg} downloading file #{file_id}")
        raise "#{inspect msg}"
    end
  end

  defp async_response(url, id, %{pid: pid, file_id: file_id} = state) do
    case HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id}) do
      {:ok, %HTTPoison.AsyncResponse{id: ^id}} -> :ok
      {:error, poison_error} ->
        Logger.error("HTTPotion returned stream_next returned non-OK response " <>
                     "#{inspect poison_error} downloading file #{file_id} ")
        raise "#{inspect poison_error}"
    end

    receive do
      %HTTPoison.AsyncStatus{code: 200, id: ^id} -> async_response(url, id, state)

      %HTTPoison.AsyncRedirect{headers: _headers, id: ^id, to: redirect_url} ->
                download_url({file_id, redirect_url}, state.directory, pid)

      %HTTPoison.AsyncStatus{code: code, id: ^id} ->
                Logger.error("HTTPotion returned non-200 status downloading file #{file_id}")
                raise "HTTP Error #{code}"

      %HTTPoison.AsyncHeaders{headers: headers, id: ^id} ->
                {_key, value} = headers
                                |> Enum.filter(fn({key, _value}) -> key == "Content-Length" end)
                                |> hd
                _bytes = value |> Integer.parse
                async_response(url, id, state)

      %HTTPoison.AsyncChunk{chunk: new_data, id: ^id} ->
                process_received_data(id, url, new_data, state)

      %HTTPoison.AsyncEnd{id: ^id} ->
                Logger.info("FileDownloader completed downloading")
                File.close(state.file)
                send(pid, {__MODULE__, :download_complete,
                  {:ok, file_id, state.chunk_no - 1, Time.diff(Time.utc_now, state.start)}})

                {:ok, state}

      %HTTPoison.Error{id: ^id, reason: {:closed, :timeout}} ->
                 Logger.warn("HTTPotion timed out waiting for response downloading file #{file_id}")
                 raise "Timed out waiting for download"

      error ->
                process_download_error(id, url, error, state)
    end
  end

  @doc """
    Handling of the empty download block
  """
  def process_received_data(id, url, "", state), do: process_received_data(id, url, [], state)

  def process_received_data(id, url, [], state) do
    async_response(url, id, state)
  end

  def process_received_data(id, url, new_data, state) when is_list(new_data) do
    process_received_data(id, url, to_string(new_data), state)
  end

  def process_received_data(id, url, new_data, %{chunk_no: chunk_no} = state)
      when is_binary(new_data) do

    process_chunk(new_data, state)
    async_response(url, id, %{state | chunk_no: chunk_no + 1})
  end

  @doc """
    Catch all for invalid data (non-binary/list) data
  """
  def process_received_data(id, url, bad_data, state) do
    Logger.error("FileDownloader: Got bad data to write into file: #{inspect bad_data}, " <>
                 "state: #{inspect state}")
    async_response(url, id, state)
  end

  @doc """
    Handling of the download error
  """
  def process_download_error(id, url, error, %{} = state) do
    case error do
      :req_timedout -> Logger.error("FileDownloader: Timed out downloading #{state.file_id}")
      _ -> Logger.error("FileDownloader: Error '#{inspect error}' downloading #{state.file_id}")
    end
    async_response(url, id, state)
  end

  def process_chunk(new_data, %{file: file} = state) do
    partname = state.chunk_no |> Integer.to_string |> String.pad_leading(5, "0")
    path = Path.join(state.directory, "part.#{partname}")
    File.write!(path, new_data, [:binary, :write])

    :done
  end

  def write_to_output(file, data) do
    case IO.binwrite(file, data) do
      :ok ->
        {:ok, file}
      error ->
        Logger.error("Error #{inspect error} trying to dump chunk into output file")
        File.close(file)
        {:error, "Error saving data to disk"}
    end
  end
end
