# Define the test NIF module FIRST - must be defined before load_nif is called
defmodule C3nif.IntegrationTest.TermNif do
  @nif_path_base "libC3nif.IntegrationTest.TermNif"

  def load_nif(priv_dir) do
    nif_path =
      priv_dir
      |> Path.join(@nif_path_base)
      |> String.to_charlist()

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Type checking tests
  def type_checks(_term), do: :erlang.nif_error(:nif_not_loaded)

  # Comparison tests
  def term_equals(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
  def term_compare(_a, _b), do: :erlang.nif_error(:nif_not_loaded)

  # Integer tests
  def get_uint_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def get_long_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def get_ulong_test(_value), do: :erlang.nif_error(:nif_not_loaded)
  def make_ulong_test(_value), do: :erlang.nif_error(:nif_not_loaded)

  # Atom tests
  def make_atom_len_test(_binary, _len), do: :erlang.nif_error(:nif_not_loaded)
  def make_existing_atom_test(_name), do: :erlang.nif_error(:nif_not_loaded)
  def get_atom_length_test(_atom), do: :erlang.nif_error(:nif_not_loaded)

  # String/charlist tests
  def make_string_test(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def make_string_len_test(_binary, _len), do: :erlang.nif_error(:nif_not_loaded)

  # List tests
  def make_empty_list_test(), do: :erlang.nif_error(:nif_not_loaded)
  def list_cell_test(_head, _tail), do: :erlang.nif_error(:nif_not_loaded)
  def get_list_cell_test(_list), do: :erlang.nif_error(:nif_not_loaded)
  def get_list_length_test(_list), do: :erlang.nif_error(:nif_not_loaded)
  def make_list_from_array_test(_count), do: :erlang.nif_error(:nif_not_loaded)

  # Tuple tests
  def get_tuple_test(_tuple), do: :erlang.nif_error(:nif_not_loaded)

  # Map tests
  def make_empty_map_test(), do: :erlang.nif_error(:nif_not_loaded)
  def map_put_test(_map, _key, _value), do: :erlang.nif_error(:nif_not_loaded)
  def map_get_test(_map, _key), do: :erlang.nif_error(:nif_not_loaded)
  def get_map_size_test(_map), do: :erlang.nif_error(:nif_not_loaded)

  # Reference tests
  def make_ref_test(), do: :erlang.nif_error(:nif_not_loaded)

  # Exception tests
  def raise_exception_test(_should_raise), do: :erlang.nif_error(:nif_not_loaded)
end

defmodule C3nif.IntegrationTest.TermTest do
  use C3nif.Case, async: false

  @moduletag :integration

  @c3_code """
  module term_test;

  import c3nif;
  import c3nif::erl_nif;
  import c3nif::env;
  import c3nif::term;
  import c3nif::safety;

  // =============================================================================
  // Type Checking Tests
  // =============================================================================

  /**
   * Returns a map with all type check results for the given term.
   */
  fn erl_nif::ErlNifTerm type_checks(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      // Build a map with all type check results
      term::Term map = term::make_new_map(&e);

      // Add each type check result
      map = map.map_put(&e, term::make_atom(&e, "is_atom"), make_bool(&e, t.is_atom(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_binary"), make_bool(&e, t.is_binary(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_ref"), make_bool(&e, t.is_ref(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_fun"), make_bool(&e, t.is_fun(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_pid"), make_bool(&e, t.is_pid(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_port"), make_bool(&e, t.is_port(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_list"), make_bool(&e, t.is_list(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_empty_list"), make_bool(&e, t.is_empty_list(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_tuple"), make_bool(&e, t.is_tuple(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_map"), make_bool(&e, t.is_map(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_number"), make_bool(&e, t.is_number(&e)))!!;
      map = map.map_put(&e, term::make_atom(&e, "is_exception"), make_bool(&e, t.is_exception(&e)))!!;

      // Add term_type as atom
      erl_nif::ErlNifTermType tt = t.term_type(&e);
      char* type_name = get_type_name(tt);
      map = map.map_put(&e, term::make_atom(&e, "term_type"), term::make_atom(&e, type_name))!!;

      return map.raw();
  }

  fn term::Term make_bool(env::Env* e, bool value) {
      if (value) {
          return term::make_atom(e, "true");
      } else {
          return term::make_atom(e, "false");
      }
  }

  fn char* get_type_name(erl_nif::ErlNifTermType tt) {
      switch (tt) {
          case erl_nif::ErlNifTermType.ATOM: return "atom";
          case erl_nif::ErlNifTermType.BITSTRING: return "bitstring";
          case erl_nif::ErlNifTermType.FLOAT: return "float";
          case erl_nif::ErlNifTermType.FUN: return "fun";
          case erl_nif::ErlNifTermType.INTEGER: return "integer";
          case erl_nif::ErlNifTermType.LIST: return "list";
          case erl_nif::ErlNifTermType.MAP: return "map";
          case erl_nif::ErlNifTermType.PID: return "pid";
          case erl_nif::ErlNifTermType.PORT: return "port";
          case erl_nif::ErlNifTermType.REFERENCE: return "reference";
          case erl_nif::ErlNifTermType.TUPLE: return "tuple";
          default: return "unknown";
      }
  }

  // =============================================================================
  // Comparison Tests
  // =============================================================================

  /**
   * Test term equality using == operator.
   */
  fn erl_nif::ErlNifTerm term_equals(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term a = term::wrap(argv[0]);
      term::Term b = term::wrap(argv[1]);

      if (a == b) {
          return term::make_atom(&e, "true").raw();
      } else {
          return term::make_atom(&e, "false").raw();
      }
  }

  /**
   * Test term comparison for ordering.
   */
  fn erl_nif::ErlNifTerm term_compare(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term a = term::wrap(argv[0]);
      term::Term b = term::wrap(argv[1]);

      int cmp = a.compare_to(b);
      if (cmp < 0) {
          return term::make_atom(&e, "lt").raw();
      } else if (cmp > 0) {
          return term::make_atom(&e, "gt").raw();
      } else {
          return term::make_atom(&e, "eq").raw();
      }
  }

  // =============================================================================
  // Integer Tests
  // =============================================================================

  fn erl_nif::ErlNifTerm get_uint_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      uint? value = t.get_uint(&e);
      if (catch err = value) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_uint(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm get_long_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      long? value = t.get_long(&e);
      if (catch err = value) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_long(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm get_ulong_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      ulong? value = t.get_ulong(&e);
      if (catch err = value) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_ulong(&e, value)).raw();
  }

  fn erl_nif::ErlNifTerm make_ulong_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      ulong? value = t.get_ulong(&e);
      if (catch err = value) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      // Round-trip: extract and recreate
      return term::make_ulong(&e, value).raw();
  }

  // =============================================================================
  // Atom Tests
  // =============================================================================

  /**
   * Create atom from binary with explicit length.
   * Takes a binary and length, creates atom from first N bytes.
   */
  fn erl_nif::ErlNifTerm make_atom_len_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term bin_term = term::wrap(argv[0]);
      term::Term len_term = term::wrap(argv[1]);

      erl_nif::ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      int? len = len_term.get_int(&e);
      if (catch err = len) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      return term::make_atom_len(&e, (char*)bin.data, (usz)len).raw();
  }

  /**
   * Test make_existing_atom - only creates if atom already exists.
   */
  fn erl_nif::ErlNifTerm make_existing_atom_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term bin_term = term::wrap(argv[0]);

      erl_nif::ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      // Need null-terminated string for make_existing_atom
      // For safety, we'll limit to reasonable atom length
      if (bin.size > 255) {
          return term::make_error_atom(&e, "too_long").raw();
      }

      char[256] buf;
      for (usz i = 0; i < bin.size; i++) {
          buf[i] = bin.data[i];
      }
      buf[bin.size] = 0;

      term::Term? atom = term::make_existing_atom(&e, &buf);
      if (catch err = atom) {
          return term::make_error_atom(&e, "not_found").raw();
      }
      return term::make_ok_tuple(&e, atom).raw();
  }

  /**
   * Get the length of an atom's name.
   */
  fn erl_nif::ErlNifTerm get_atom_length_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term t = term::wrap(argv[0]);

      uint? len = t.get_atom_length(&e);
      if (catch err = len) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_uint(&e, len)).raw();
  }

  // =============================================================================
  // String/Charlist Tests
  // =============================================================================

  /**
   * Create a charlist from a binary.
   */
  fn erl_nif::ErlNifTerm make_string_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term bin_term = term::wrap(argv[0]);

      erl_nif::ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      // Need null-terminated for make_string
      if (bin.size > 1023) {
          return term::make_error_atom(&e, "too_long").raw();
      }

      char[1024] buf;
      for (usz i = 0; i < bin.size; i++) {
          buf[i] = bin.data[i];
      }
      buf[bin.size] = 0;

      return term::make_string(&e, &buf).raw();
  }

  /**
   * Create a charlist from a binary with explicit length.
   */
  fn erl_nif::ErlNifTerm make_string_len_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term bin_term = term::wrap(argv[0]);
      term::Term len_term = term::wrap(argv[1]);

      erl_nif::ErlNifBinary? bin = bin_term.inspect_binary(&e);
      if (catch err = bin) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      int? len = len_term.get_int(&e);
      if (catch err = len) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      return term::make_string_len(&e, (char*)bin.data, (usz)len).raw();
  }

  // =============================================================================
  // List Tests
  // =============================================================================

  /**
   * Create an empty list.
   */
  fn erl_nif::ErlNifTerm make_empty_list_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      return term::make_empty_list(&e).raw();
  }

  /**
   * Create a list cell [head | tail].
   */
  fn erl_nif::ErlNifTerm list_cell_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term head = term::wrap(argv[0]);
      term::Term tail = term::wrap(argv[1]);

      return term::make_list_cell(&e, head, tail).raw();
  }

  /**
   * Get the head and tail of a list.
   */
  fn erl_nif::ErlNifTerm get_list_cell_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term list = term::wrap(argv[0]);

      term::Term head;
      term::Term tail;
      if (catch err = list.get_list_cell(&e, &head, &tail)) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      // Return {head, tail}
      erl_nif::ErlNifTerm[2] elements = { head.raw(), tail.raw() };
      return term::make_tuple_from_array(&e, elements[0:2]).raw();
  }

  /**
   * Get the length of a list.
   */
  fn erl_nif::ErlNifTerm get_list_length_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term list = term::wrap(argv[0]);

      uint? len = list.get_list_length(&e);
      if (catch err = len) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_uint(&e, len)).raw();
  }

  /**
   * Create a list from an array of integers [1, 2, 3, ..., count].
   */
  fn erl_nif::ErlNifTerm make_list_from_array_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term count_term = term::wrap(argv[0]);

      int? count = count_term.get_int(&e);
      if (catch err = count) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      if (count < 0 || count > 100) {
          return term::make_error_atom(&e, "invalid_count").raw();
      }

      // Build array of terms
      erl_nif::ErlNifTerm[100] arr;
      for (int i = 0; i < count; i++) {
          arr[i] = term::make_int(&e, i + 1).raw();
      }

      return term::make_list_from_array(&e, arr[0:(usz)count]).raw();
  }

  // =============================================================================
  // Tuple Tests
  // =============================================================================

  /**
   * Get tuple elements as a list.
   */
  fn erl_nif::ErlNifTerm get_tuple_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term tuple = term::wrap(argv[0]);

      erl_nif::ErlNifTerm* elements;
      int? arity = tuple.get_tuple(&e, &elements);
      if (catch err = arity) {
          return term::make_error_atom(&e, "badarg").raw();
      }

      // Convert to list
      term::Term list = term::make_empty_list(&e);
      // Build list in reverse order
      for (int i = arity - 1; i >= 0; i--) {
          list = term::make_list_cell(&e, term::wrap(elements[i]), list);
      }

      return term::make_ok_tuple(&e, list).raw();
  }

  // =============================================================================
  // Map Tests
  // =============================================================================

  /**
   * Create an empty map.
   */
  fn erl_nif::ErlNifTerm make_empty_map_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      return term::make_new_map(&e).raw();
  }

  /**
   * Put a key-value pair into a map.
   */
  fn erl_nif::ErlNifTerm map_put_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term map = term::wrap(argv[0]);
      term::Term key = term::wrap(argv[1]);
      term::Term value = term::wrap(argv[2]);

      term::Term? new_map = map.map_put(&e, key, value);
      if (catch err = new_map) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return new_map.raw();
  }

  /**
   * Get a value from a map by key.
   */
  fn erl_nif::ErlNifTerm map_get_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term map = term::wrap(argv[0]);
      term::Term key = term::wrap(argv[1]);

      term::Term? value = map.map_get(&e, key);
      if (catch err = value) {
          return term::make_error_atom(&e, "not_found").raw();
      }
      return term::make_ok_tuple(&e, value).raw();
  }

  /**
   * Get the size of a map.
   */
  fn erl_nif::ErlNifTerm get_map_size_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term map = term::wrap(argv[0]);

      usz? size = map.get_map_size(&e);
      if (catch err = size) {
          return term::make_error_atom(&e, "badarg").raw();
      }
      return term::make_ok_tuple(&e, term::make_ulong(&e, (ulong)size)).raw();
  }

  // =============================================================================
  // Reference Tests
  // =============================================================================

  /**
   * Create a unique reference.
   */
  fn erl_nif::ErlNifTerm make_ref_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      return term::make_ref(&e).raw();
  }

  // =============================================================================
  // Exception Tests
  // =============================================================================

  /**
   * Test raise_exception.
   * If arg is :raise, raises an exception with reason :test_exception.
   * Otherwise returns :ok.
   */
  fn erl_nif::ErlNifTerm raise_exception_test(
      erl_nif::ErlNifEnv* env_raw, CInt argc, erl_nif::ErlNifTerm* argv
  ) {
      env::Env e = env::wrap(env_raw);
      term::Term arg = term::wrap(argv[0]);

      // Check if we should raise
      term::Term raise_atom = term::make_atom(&e, "raise");
      if (arg == raise_atom) {
          term::Term reason = term::make_atom(&e, "test_exception");
          return term::raise_exception(&e, reason).raw();
      }

      return term::make_atom(&e, "ok").raw();
  }

  // =============================================================================
  // NIF Entry
  // =============================================================================

  erl_nif::ErlNifFunc[20] nif_funcs = {
      // Type checking
      { .name = "type_checks", .arity = 1, .fptr = &type_checks, .flags = 0 },

      // Comparison
      { .name = "term_equals", .arity = 2, .fptr = &term_equals, .flags = 0 },
      { .name = "term_compare", .arity = 2, .fptr = &term_compare, .flags = 0 },

      // Integer
      { .name = "get_uint_test", .arity = 1, .fptr = &get_uint_test, .flags = 0 },
      { .name = "get_long_test", .arity = 1, .fptr = &get_long_test, .flags = 0 },
      { .name = "get_ulong_test", .arity = 1, .fptr = &get_ulong_test, .flags = 0 },
      { .name = "make_ulong_test", .arity = 1, .fptr = &make_ulong_test, .flags = 0 },

      // Atom
      { .name = "make_atom_len_test", .arity = 2, .fptr = &make_atom_len_test, .flags = 0 },
      { .name = "make_existing_atom_test", .arity = 1, .fptr = &make_existing_atom_test, .flags = 0 },
      { .name = "get_atom_length_test", .arity = 1, .fptr = &get_atom_length_test, .flags = 0 },

      // String
      { .name = "make_string_test", .arity = 1, .fptr = &make_string_test, .flags = 0 },
      { .name = "make_string_len_test", .arity = 2, .fptr = &make_string_len_test, .flags = 0 },

      // List
      { .name = "make_empty_list_test", .arity = 0, .fptr = &make_empty_list_test, .flags = 0 },
      { .name = "list_cell_test", .arity = 2, .fptr = &list_cell_test, .flags = 0 },
      { .name = "get_list_cell_test", .arity = 1, .fptr = &get_list_cell_test, .flags = 0 },
      { .name = "get_list_length_test", .arity = 1, .fptr = &get_list_length_test, .flags = 0 },
      { .name = "make_list_from_array_test", .arity = 1, .fptr = &make_list_from_array_test, .flags = 0 },

      // Tuple
      { .name = "get_tuple_test", .arity = 1, .fptr = &get_tuple_test, .flags = 0 },

      // Map
      { .name = "make_empty_map_test", .arity = 0, .fptr = &make_empty_map_test, .flags = 0 },
      { .name = "map_put_test", .arity = 3, .fptr = &map_put_test, .flags = 0 },
  };

  erl_nif::ErlNifFunc[3] nif_funcs2 = {
      { .name = "map_get_test", .arity = 2, .fptr = &map_get_test, .flags = 0 },
      { .name = "get_map_size_test", .arity = 1, .fptr = &get_map_size_test, .flags = 0 },
      { .name = "make_ref_test", .arity = 0, .fptr = &make_ref_test, .flags = 0 },
  };

  erl_nif::ErlNifFunc[1] nif_funcs3 = {
      { .name = "raise_exception_test", .arity = 1, .fptr = &raise_exception_test, .flags = 0 },
  };

  // Combined function array for entry
  erl_nif::ErlNifFunc[24] all_nif_funcs = {
      // Type checking
      { .name = "type_checks", .arity = 1, .fptr = &type_checks, .flags = 0 },
      // Comparison
      { .name = "term_equals", .arity = 2, .fptr = &term_equals, .flags = 0 },
      { .name = "term_compare", .arity = 2, .fptr = &term_compare, .flags = 0 },
      // Integer
      { .name = "get_uint_test", .arity = 1, .fptr = &get_uint_test, .flags = 0 },
      { .name = "get_long_test", .arity = 1, .fptr = &get_long_test, .flags = 0 },
      { .name = "get_ulong_test", .arity = 1, .fptr = &get_ulong_test, .flags = 0 },
      { .name = "make_ulong_test", .arity = 1, .fptr = &make_ulong_test, .flags = 0 },
      // Atom
      { .name = "make_atom_len_test", .arity = 2, .fptr = &make_atom_len_test, .flags = 0 },
      { .name = "make_existing_atom_test", .arity = 1, .fptr = &make_existing_atom_test, .flags = 0 },
      { .name = "get_atom_length_test", .arity = 1, .fptr = &get_atom_length_test, .flags = 0 },
      // String
      { .name = "make_string_test", .arity = 1, .fptr = &make_string_test, .flags = 0 },
      { .name = "make_string_len_test", .arity = 2, .fptr = &make_string_len_test, .flags = 0 },
      // List
      { .name = "make_empty_list_test", .arity = 0, .fptr = &make_empty_list_test, .flags = 0 },
      { .name = "list_cell_test", .arity = 2, .fptr = &list_cell_test, .flags = 0 },
      { .name = "get_list_cell_test", .arity = 1, .fptr = &get_list_cell_test, .flags = 0 },
      { .name = "get_list_length_test", .arity = 1, .fptr = &get_list_length_test, .flags = 0 },
      { .name = "make_list_from_array_test", .arity = 1, .fptr = &make_list_from_array_test, .flags = 0 },
      // Tuple
      { .name = "get_tuple_test", .arity = 1, .fptr = &get_tuple_test, .flags = 0 },
      // Map
      { .name = "make_empty_map_test", .arity = 0, .fptr = &make_empty_map_test, .flags = 0 },
      { .name = "map_put_test", .arity = 3, .fptr = &map_put_test, .flags = 0 },
      { .name = "map_get_test", .arity = 2, .fptr = &map_get_test, .flags = 0 },
      { .name = "get_map_size_test", .arity = 1, .fptr = &get_map_size_test, .flags = 0 },
      // Reference
      { .name = "make_ref_test", .arity = 0, .fptr = &make_ref_test, .flags = 0 },
      // Exception
      { .name = "raise_exception_test", .arity = 1, .fptr = &raise_exception_test, .flags = 0 },
  };

  erl_nif::ErlNifEntry nif_entry;

  fn erl_nif::ErlNifEntry* nif_init() @export("nif_init") {
      nif_entry = c3nif::make_nif_entry(
          "Elixir.C3nif.IntegrationTest.TermNif",
          &all_nif_funcs,
          24,
          null,
          null
      );
      return &nif_entry;
  }
  """

  setup_all do
    case compile_test_nif(
           C3nif.IntegrationTest.TermNif,
           @c3_code,
           otp_app: :c3nif
         ) do
      {:ok, lib_path} ->
        priv_dir = :code.priv_dir(:c3nif) |> to_string()
        nif_name = "libC3nif.IntegrationTest.TermNif#{C3nif.nif_extension()}"
        dest_path = Path.join(priv_dir, nif_name)

        File.mkdir_p!(priv_dir)
        File.cp!(lib_path, dest_path)

        case C3nif.IntegrationTest.TermNif.load_nif(priv_dir) do
          :ok -> {:ok, lib_path: dest_path}
          {:error, reason} -> raise "Failed to load NIF: #{inspect(reason)}"
        end

      {:error, {:compile_failed, _exit_code, output}} ->
        raise "Compilation failed: #{output}"

      {:error, reason} ->
        raise "Compilation failed: #{inspect(reason)}"
    end
  end

  # =============================================================================
  # Type Checking Tests
  # =============================================================================

  describe "type_checks/1" do
    test "correctly identifies atom" do
      result = C3nif.IntegrationTest.TermNif.type_checks(:hello)
      assert result[:is_atom] == true
      assert result[:is_binary] == false
      assert result[:is_list] == false
      assert result[:is_number] == false
      assert result[:term_type] == :atom
    end

    test "correctly identifies integer" do
      result = C3nif.IntegrationTest.TermNif.type_checks(42)
      assert result[:is_atom] == false
      assert result[:is_number] == true
      assert result[:term_type] == :integer
    end

    test "correctly identifies float" do
      result = C3nif.IntegrationTest.TermNif.type_checks(3.14)
      assert result[:is_number] == true
      assert result[:term_type] == :float
    end

    test "correctly identifies binary" do
      result = C3nif.IntegrationTest.TermNif.type_checks("hello")
      assert result[:is_binary] == true
      assert result[:term_type] == :bitstring
    end

    test "correctly identifies list" do
      result = C3nif.IntegrationTest.TermNif.type_checks([1, 2, 3])
      assert result[:is_list] == true
      assert result[:is_empty_list] == false
      assert result[:term_type] == :list
    end

    test "correctly identifies empty list" do
      result = C3nif.IntegrationTest.TermNif.type_checks([])
      assert result[:is_list] == true
      assert result[:is_empty_list] == true
      assert result[:term_type] == :list
    end

    test "correctly identifies tuple" do
      result = C3nif.IntegrationTest.TermNif.type_checks({1, 2, 3})
      assert result[:is_tuple] == true
      assert result[:term_type] == :tuple
    end

    test "correctly identifies map" do
      result = C3nif.IntegrationTest.TermNif.type_checks(%{a: 1})
      assert result[:is_map] == true
      assert result[:term_type] == :map
    end

    test "correctly identifies reference" do
      ref = make_ref()
      result = C3nif.IntegrationTest.TermNif.type_checks(ref)
      assert result[:is_ref] == true
      assert result[:term_type] == :reference
    end

    test "correctly identifies pid" do
      result = C3nif.IntegrationTest.TermNif.type_checks(self())
      assert result[:is_pid] == true
      assert result[:term_type] == :pid
    end

    test "correctly identifies function" do
      result = C3nif.IntegrationTest.TermNif.type_checks(fn x -> x end)
      assert result[:is_fun] == true
      assert result[:term_type] == :fun
    end
  end

  # =============================================================================
  # Comparison Tests
  # =============================================================================

  describe "term_equals/2" do
    test "returns true for identical atoms" do
      assert C3nif.IntegrationTest.TermNif.term_equals(:hello, :hello) == true
    end

    test "returns false for different atoms" do
      assert C3nif.IntegrationTest.TermNif.term_equals(:hello, :world) == false
    end

    test "returns true for identical integers" do
      assert C3nif.IntegrationTest.TermNif.term_equals(42, 42) == true
    end

    test "returns false for different integers" do
      assert C3nif.IntegrationTest.TermNif.term_equals(42, 43) == false
    end

    test "returns true for identical lists" do
      assert C3nif.IntegrationTest.TermNif.term_equals([1, 2, 3], [1, 2, 3]) == true
    end

    test "returns false for different types" do
      assert C3nif.IntegrationTest.TermNif.term_equals(42, "42") == false
    end
  end

  describe "term_compare/2" do
    test "returns eq for equal values" do
      assert C3nif.IntegrationTest.TermNif.term_compare(42, 42) == :eq
    end

    test "returns lt when first is less" do
      assert C3nif.IntegrationTest.TermNif.term_compare(1, 2) == :lt
    end

    test "returns gt when first is greater" do
      assert C3nif.IntegrationTest.TermNif.term_compare(2, 1) == :gt
    end

    test "compares atoms alphabetically" do
      assert C3nif.IntegrationTest.TermNif.term_compare(:apple, :banana) == :lt
      assert C3nif.IntegrationTest.TermNif.term_compare(:banana, :apple) == :gt
    end

    test "compares different types by Erlang term ordering" do
      # number < atom < reference < fun < port < pid < tuple < map < list < bitstring
      assert C3nif.IntegrationTest.TermNif.term_compare(1, :atom) == :lt
      assert C3nif.IntegrationTest.TermNif.term_compare(:atom, {1, 2}) == :lt
    end
  end

  # =============================================================================
  # Integer Tests
  # =============================================================================

  describe "get_uint_test/1" do
    test "extracts positive integer" do
      assert C3nif.IntegrationTest.TermNif.get_uint_test(42) == {:ok, 42}
    end

    test "extracts zero" do
      assert C3nif.IntegrationTest.TermNif.get_uint_test(0) == {:ok, 0}
    end

    test "returns error for negative integer" do
      assert C3nif.IntegrationTest.TermNif.get_uint_test(-1) == {:error, :badarg}
    end

    test "returns error for non-integer" do
      assert C3nif.IntegrationTest.TermNif.get_uint_test(:atom) == {:error, :badarg}
    end
  end

  describe "get_long_test/1" do
    test "extracts positive long" do
      assert C3nif.IntegrationTest.TermNif.get_long_test(1_000_000_000) == {:ok, 1_000_000_000}
    end

    test "extracts negative long" do
      assert C3nif.IntegrationTest.TermNif.get_long_test(-1_000_000_000) == {:ok, -1_000_000_000}
    end

    test "returns error for non-integer" do
      assert C3nif.IntegrationTest.TermNif.get_long_test("string") == {:error, :badarg}
    end
  end

  describe "get_ulong_test/1" do
    test "extracts large positive value" do
      assert C3nif.IntegrationTest.TermNif.get_ulong_test(4_000_000_000) == {:ok, 4_000_000_000}
    end

    test "returns error for negative" do
      assert C3nif.IntegrationTest.TermNif.get_ulong_test(-1) == {:error, :badarg}
    end
  end

  describe "make_ulong_test/1" do
    test "round-trips large value" do
      assert C3nif.IntegrationTest.TermNif.make_ulong_test(4_000_000_000) == 4_000_000_000
    end
  end

  # =============================================================================
  # Atom Tests
  # =============================================================================

  describe "make_atom_len_test/2" do
    test "creates atom from first N bytes" do
      assert C3nif.IntegrationTest.TermNif.make_atom_len_test("hello_world", 5) == :hello
    end

    test "creates full atom when length matches" do
      assert C3nif.IntegrationTest.TermNif.make_atom_len_test("test", 4) == :test
    end
  end

  describe "make_existing_atom_test/1" do
    test "returns existing atom" do
      # :ok should always exist
      assert C3nif.IntegrationTest.TermNif.make_existing_atom_test("ok") == {:ok, :ok}
    end

    test "returns error for non-existing atom" do
      # Use a very unlikely atom name
      assert C3nif.IntegrationTest.TermNif.make_existing_atom_test("__this_atom_should_not_exist_xyz123__") ==
               {:error, :not_found}
    end
  end

  describe "get_atom_length_test/1" do
    test "returns length of atom name" do
      assert C3nif.IntegrationTest.TermNif.get_atom_length_test(:hello) == {:ok, 5}
    end

    test "returns length of longer atom" do
      assert C3nif.IntegrationTest.TermNif.get_atom_length_test(:hello_world) == {:ok, 11}
    end

    test "returns error for non-atom" do
      assert C3nif.IntegrationTest.TermNif.get_atom_length_test(123) == {:error, :badarg}
    end
  end

  # =============================================================================
  # String/Charlist Tests
  # =============================================================================

  describe "make_string_test/1" do
    test "creates charlist from binary" do
      assert C3nif.IntegrationTest.TermNif.make_string_test("hello") == ~c"hello"
    end

    test "creates empty charlist" do
      assert C3nif.IntegrationTest.TermNif.make_string_test("") == ~c""
    end
  end

  describe "make_string_len_test/2" do
    test "creates charlist with explicit length" do
      assert C3nif.IntegrationTest.TermNif.make_string_len_test("hello_world", 5) == ~c"hello"
    end

    test "creates shorter charlist" do
      assert C3nif.IntegrationTest.TermNif.make_string_len_test("test", 2) == ~c"te"
    end
  end

  # =============================================================================
  # List Tests
  # =============================================================================

  describe "make_empty_list_test/0" do
    test "creates empty list" do
      assert C3nif.IntegrationTest.TermNif.make_empty_list_test() == []
    end
  end

  describe "list_cell_test/2" do
    test "creates list cell" do
      assert C3nif.IntegrationTest.TermNif.list_cell_test(1, [2, 3]) == [1, 2, 3]
    end

    test "creates single element list" do
      assert C3nif.IntegrationTest.TermNif.list_cell_test(:a, []) == [:a]
    end

    test "creates improper list" do
      assert C3nif.IntegrationTest.TermNif.list_cell_test(:a, :b) == [:a | :b]
    end
  end

  describe "get_list_cell_test/1" do
    test "extracts head and tail" do
      assert C3nif.IntegrationTest.TermNif.get_list_cell_test([1, 2, 3]) == {1, [2, 3]}
    end

    test "extracts from single element list" do
      assert C3nif.IntegrationTest.TermNif.get_list_cell_test([:a]) == {:a, []}
    end

    test "returns error for empty list" do
      assert C3nif.IntegrationTest.TermNif.get_list_cell_test([]) == {:error, :badarg}
    end

    test "returns error for non-list" do
      assert C3nif.IntegrationTest.TermNif.get_list_cell_test(:atom) == {:error, :badarg}
    end
  end

  describe "get_list_length_test/1" do
    test "returns length of list" do
      assert C3nif.IntegrationTest.TermNif.get_list_length_test([1, 2, 3]) == {:ok, 3}
    end

    test "returns zero for empty list" do
      assert C3nif.IntegrationTest.TermNif.get_list_length_test([]) == {:ok, 0}
    end

    test "returns error for non-list" do
      assert C3nif.IntegrationTest.TermNif.get_list_length_test(:atom) == {:error, :badarg}
    end
  end

  describe "make_list_from_array_test/1" do
    test "creates list from count" do
      assert C3nif.IntegrationTest.TermNif.make_list_from_array_test(5) == [1, 2, 3, 4, 5]
    end

    test "creates empty list for zero" do
      assert C3nif.IntegrationTest.TermNif.make_list_from_array_test(0) == []
    end

    test "creates single element list" do
      assert C3nif.IntegrationTest.TermNif.make_list_from_array_test(1) == [1]
    end
  end

  # =============================================================================
  # Tuple Tests
  # =============================================================================

  describe "get_tuple_test/1" do
    test "extracts tuple elements as list" do
      assert C3nif.IntegrationTest.TermNif.get_tuple_test({1, 2, 3}) == {:ok, [1, 2, 3]}
    end

    test "extracts empty tuple" do
      assert C3nif.IntegrationTest.TermNif.get_tuple_test({}) == {:ok, []}
    end

    test "extracts single element tuple" do
      assert C3nif.IntegrationTest.TermNif.get_tuple_test({:a}) == {:ok, [:a]}
    end

    test "returns error for non-tuple" do
      assert C3nif.IntegrationTest.TermNif.get_tuple_test([1, 2, 3]) == {:error, :badarg}
    end
  end

  # =============================================================================
  # Map Tests
  # =============================================================================

  describe "make_empty_map_test/0" do
    test "creates empty map" do
      assert C3nif.IntegrationTest.TermNif.make_empty_map_test() == %{}
    end
  end

  describe "map_put_test/3" do
    test "puts key-value into empty map" do
      map = C3nif.IntegrationTest.TermNif.make_empty_map_test()
      assert C3nif.IntegrationTest.TermNif.map_put_test(map, :key, :value) == %{key: :value}
    end

    test "puts key-value into existing map" do
      assert C3nif.IntegrationTest.TermNif.map_put_test(%{a: 1}, :b, 2) == %{a: 1, b: 2}
    end

    test "overwrites existing key" do
      assert C3nif.IntegrationTest.TermNif.map_put_test(%{a: 1}, :a, 2) == %{a: 2}
    end

    test "returns error for non-map" do
      assert C3nif.IntegrationTest.TermNif.map_put_test(:not_a_map, :key, :value) == {:error, :badarg}
    end
  end

  describe "map_get_test/2" do
    test "gets value by key" do
      assert C3nif.IntegrationTest.TermNif.map_get_test(%{a: 1, b: 2}, :a) == {:ok, 1}
    end

    test "returns error for missing key" do
      assert C3nif.IntegrationTest.TermNif.map_get_test(%{a: 1}, :b) == {:error, :not_found}
    end

    test "returns error for non-map" do
      assert C3nif.IntegrationTest.TermNif.map_get_test(:not_a_map, :key) == {:error, :not_found}
    end
  end

  describe "get_map_size_test/1" do
    test "returns size of map" do
      assert C3nif.IntegrationTest.TermNif.get_map_size_test(%{a: 1, b: 2, c: 3}) == {:ok, 3}
    end

    test "returns zero for empty map" do
      assert C3nif.IntegrationTest.TermNif.get_map_size_test(%{}) == {:ok, 0}
    end

    test "returns error for non-map" do
      assert C3nif.IntegrationTest.TermNif.get_map_size_test(:not_a_map) == {:error, :badarg}
    end
  end

  # =============================================================================
  # Reference Tests
  # =============================================================================

  describe "make_ref_test/0" do
    test "creates a reference" do
      ref = C3nif.IntegrationTest.TermNif.make_ref_test()
      assert is_reference(ref)
    end

    test "creates unique references" do
      ref1 = C3nif.IntegrationTest.TermNif.make_ref_test()
      ref2 = C3nif.IntegrationTest.TermNif.make_ref_test()
      assert ref1 != ref2
    end
  end

  # =============================================================================
  # Exception Tests
  # =============================================================================

  describe "raise_exception_test/1" do
    test "returns ok when not raising" do
      assert C3nif.IntegrationTest.TermNif.raise_exception_test(:dont_raise) == :ok
    end

    test "raises exception when requested" do
      assert_raise ErlangError, ~r/test_exception/, fn ->
        C3nif.IntegrationTest.TermNif.raise_exception_test(:raise)
      end
    end
  end
end
