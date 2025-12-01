defmodule C3nif.Parser do
  @moduledoc """
  Parse C3 source code to extract NIF function metadata.

  This module analyzes C3 source files to find NIF functions based on their
  signature pattern and extracts metadata from `<* @nif ... *>` doc comment
  annotations.

  ## NIF Detection

  NIF functions are detected by their signature pattern:

      fn erl_nif::ErlNifTerm function_name(
          erl_nif::ErlNifEnv* env, CInt argc, erl_nif::ErlNifTerm* argv
      ) { ... }

  ## Annotations

  Metadata is extracted from C3's doc comment syntax (`<* ... *>`).
  We use `nif:` prefix (not `@nif`) to avoid conflicts with C3's contract syntax:

      <* nif: arity = 2 *>
      fn erl_nif::ErlNifTerm add(...) { ... }

      <* nif: arity = 1, dirty = cpu *>
      fn erl_nif::ErlNifTerm heavy_compute(...) { ... }

      <* nif: name = "custom_name", arity = 2 *>
      fn erl_nif::ErlNifTerm internal_name(...) { ... }

  ## Callbacks

  The following callbacks are auto-detected by function name and signature:

  - `on_load` - `fn CInt on_load(erl_nif::ErlNifEnv*, void**, erl_nif::ErlNifTerm)`
  - `on_unload` - `fn void on_unload(erl_nif::ErlNifEnv*, void*)`
  """

  defmodule NifFunction do
    @moduledoc """
    Metadata for a NIF function extracted from C3 source.
    """
    defstruct [
      :c3_name,
      :elixir_name,
      :arity,
      :dirty,
      :line
    ]

    @type dirty :: :cpu | :io | nil

    @type t :: %__MODULE__{
            c3_name: String.t(),
            elixir_name: String.t(),
            arity: non_neg_integer(),
            dirty: dirty(),
            line: pos_integer()
          }
  end

  defmodule Callbacks do
    @moduledoc """
    Detected callback functions.
    """
    defstruct [
      on_load: nil,
      on_unload: nil
    ]

    @type t :: %__MODULE__{
            on_load: String.t() | nil,
            on_unload: String.t() | nil
          }
  end

  @doc """
  Parse C3 source code and extract NIF function metadata.

  Returns a list of `NifFunction` structs for all detected NIF functions.
  """
  @spec parse_nifs(String.t()) :: [NifFunction.t()]
  def parse_nifs(c3_source) do
    # Find all NIF-signature functions with their line numbers
    nif_matches = find_nif_signatures(c3_source)

    # For each match, look for a preceding @nif annotation
    Enum.flat_map(nif_matches, fn {c3_name, line, start_pos} ->
      case find_nif_annotation(c3_source, start_pos) do
        {:ok, annotation} ->
          [build_nif_function(c3_name, line, annotation)]

        :error ->
          # No @nif annotation found - skip this function
          []
      end
    end)
  end

  @doc """
  Parse C3 source code and detect callback functions.

  Returns a `Callbacks` struct with detected on_load and on_unload functions.
  """
  @spec parse_callbacks(String.t()) :: Callbacks.t()
  def parse_callbacks(c3_source) do
    %Callbacks{
      on_load: find_on_load(c3_source),
      on_unload: find_on_unload(c3_source)
    }
  end

  @doc """
  Parse both NIFs and callbacks from C3 source.

  Returns `{nifs, callbacks}` tuple.
  """
  @spec parse(String.t()) :: {[NifFunction.t()], Callbacks.t()}
  def parse(c3_source) do
    {parse_nifs(c3_source), parse_callbacks(c3_source)}
  end

  # ===========================================================================
  # NIF Signature Detection
  # ===========================================================================

  # Pattern to match NIF function signatures
  # Matches: fn ErlNifTerm function_name(ErlNifEnv*
  @nif_signature_pattern ~r/fn\s+ErlNifTerm\s+(\w+)\s*\(\s*ErlNifEnv\s*\*/

  defp find_nif_signatures(c3_source) do
    lines = String.split(c3_source, "\n")

    @nif_signature_pattern
    |> Regex.scan(c3_source, return: :index)
    |> Enum.map(fn [{start_pos, _len}, {name_start, name_len}] ->
      c3_name = String.slice(c3_source, name_start, name_len)
      line = count_lines_before(c3_source, start_pos, lines)
      {c3_name, line, start_pos}
    end)
  end

  defp count_lines_before(source, pos, _lines) do
    source
    |> String.slice(0, pos)
    |> String.split("\n")
    |> length()
  end

  # ===========================================================================
  # Annotation Parsing
  # ===========================================================================

  # Pattern to find doc comment blocks: <* ... *>
  @doc_comment_pattern ~r/<\*(?<content>[\s\S]*?)\*>/

  # Patterns for extracting nif: annotation fields
  # Use "nif:" prefix to avoid C3 contract syntax conflicts
  @nif_annotation_pattern ~r/\bnif\s*:/
  @arity_pattern ~r/arity\s*=\s*(\d+)/
  @dirty_pattern ~r/dirty\s*=\s*(\w+)/
  @name_pattern ~r/name\s*=\s*"([^"]+)"/

  defp find_nif_annotation(c3_source, fn_start_pos) do
    # Look backward from the function to find a doc comment
    before_fn = String.slice(c3_source, 0, fn_start_pos)

    # Find the last doc comment before the function
    case find_last_doc_comment(before_fn) do
      nil ->
        :error

      {comment_content, comment_end_pos} ->
        # Check if there's only whitespace between comment and function
        between = String.slice(before_fn, comment_end_pos, fn_start_pos - comment_end_pos)

        if String.match?(between, ~r/^\s*$/) and String.match?(comment_content, @nif_annotation_pattern) do
          {:ok, parse_annotation(comment_content)}
        else
          :error
        end
    end
  end

  defp find_last_doc_comment(source) do
    @doc_comment_pattern
    |> Regex.scan(source, return: :index, capture: :all)
    |> List.last()
    |> case do
      nil ->
        nil

      [{start_pos, len}, {content_start, content_len}] ->
        content = String.slice(source, content_start, content_len)
        end_pos = start_pos + len
        {content, end_pos}
    end
  end

  defp parse_annotation(content) do
    %{
      arity: extract_arity(content),
      dirty: extract_dirty(content),
      name: extract_name(content)
    }
  end

  defp extract_arity(content) do
    case Regex.run(@arity_pattern, content) do
      [_, arity_str] -> String.to_integer(arity_str)
      nil -> nil
    end
  end

  defp extract_dirty(content) do
    case Regex.run(@dirty_pattern, content) do
      [_, "cpu"] -> :cpu
      [_, "io"] -> :io
      _ -> nil
    end
  end

  defp extract_name(content) do
    case Regex.run(@name_pattern, content) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp build_nif_function(c3_name, line, annotation) do
    %NifFunction{
      c3_name: c3_name,
      elixir_name: annotation[:name] || c3_name,
      arity: annotation[:arity],
      dirty: annotation[:dirty],
      line: line
    }
  end

  # ===========================================================================
  # Callback Detection
  # ===========================================================================

  # Pattern for on_load: fn CInt on_load(ErlNifEnv*
  @on_load_pattern ~r/fn\s+CInt\s+(on_load)\s*\(\s*ErlNifEnv\s*\*/

  # Pattern for on_unload: fn void on_unload(ErlNifEnv*
  @on_unload_pattern ~r/fn\s+void\s+(on_unload)\s*\(\s*ErlNifEnv\s*\*/

  defp find_on_load(c3_source) do
    case Regex.run(@on_load_pattern, c3_source) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp find_on_unload(c3_source) do
    case Regex.run(@on_unload_pattern, c3_source) do
      [_, name] -> name
      nil -> nil
    end
  end
end
