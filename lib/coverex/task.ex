defmodule Coverex.Task do
    require EEx

    require Logger

    @type mod_cover :: [{String.t, {integer, integer}}]
    @type fun_cover :: [{mfa, {integer, integer}}]

    @doc """
    Starts the `Coverex` coverage data generation. An additional option
    is

        log: :error

    which sets the log-level of the Elixir Logger application. Default value
    is `:error`. For debugging purposes, it can be set to :debug. In this case,
    the output is quite noisy...
    """
    def start(compile_path, opts) do
      Mix.shell.info "Coverex compiling modules ... "
      Mix.shell.info "compile_path is #{inspect compile_path}"
      Mix.shell.info "Options are: #{inspect opts}"
      :cover.start
      :cover.compile_beam_directory(compile_path |> to_char_list)

      if :application.get_env(:cover, :started) != {:ok, true} do
        :application.set_env(:cover, :started, true)
      end

      output = opts[:output]
      fn() ->
        Mix.shell.info "\nGenerating cover results ... "
        Application.ensure_started(:logger)
        Logger.configure(level: Keyword.get(opts, :log, :error))
        File.mkdir_p!(output)

        # determine all modules to analyze
        all_modules = :cover.modules
          |> filter_modules(Keyword.get(opts, :ignore_modules, []))

        Enum.each all_modules, fn(mod) ->
          # :cover.analyse_to_file(mod, '#{output}/#{mod}.1.html', [:html])
          write_html_file(mod, output)
        end
        {mods, funcs} = coverage_data(all_modules)
        write_module_overview(mods, output)
        write_function_overview(funcs, output)
        generate_assets(output)
        # Text overview output
        if Keyword.get(opts, :console_log, true) do
          puts_module_overview(mods)
        end
        # ask for coveralls option
        if post_to_coveralls?(opts) && (ci = ci_info()) do
          post_coveralls(:cover.modules, output, ci)
        end
      end
    end

    def filter_modules(all_modules, ignore_list) do
      all_modules
        |> Enum.reject(fn m ->
            ignore_list |> Enum.member?(m)
          end)
    end

    @doc "is post to coveralls requested?"
    def post_to_coveralls?(opts) do
      Keyword.get(opts, :coveralls, false)
    end

    @doc "gets CI information from environment"
    @spec ci_info(%{String.t => String.t}) :: %{atom => String.t} | nil
    def ci_info(env \\ System.get_env()) do
      cond do
        running_travis?(env) -> travis_ci_info(env)
        running_buildkite?(env) -> buildkite_ci_info(env)
        true -> nil
      end
    end

    @spec running_travis?(%{String.t => String.t}) :: bool
    def running_travis?(env \\ System.get_env()) do
      env["TRAVIS"] == "true"
    end

    @spec running_buildkite?(%{String.t => String.t}) :: bool
    def running_buildkite?(env \\ System.get_env()) do
      env["BUILDKITE"] == "true"
    end

    @doc "gets the travis ci info out of the environment"
    @spec travis_ci_info(%{String.t => String.t}) :: %{atom => String.t}
    def travis_ci_info(env \\ System.get_env()) do
      ci_info = %{
        service_name: "travis-ci",
        service_job_id: env["TRAVIS_JOB_ID"]
      }
      if (pull_request = env["TRAVIS_PULL_REQUEST"]) in ["false", nil] do
        ci_info
      else
        Map.put(ci_info, :service_pull_request, pull_request)
      end
    end

    @doc "gets the buildkite ci info out of the environment"
    @spec travis_ci_info(%{String.t => String.t}) :: %{atom => String.t}
    def buildkite_ci_info(env \\ System.get_env()) do
      ci_info = %{
        service_name: "buildkite",
        service_number: env["BUILDKITE_BUILD_NUMBER"],
        service_job_id: env["BUILDKITE_JOB_ID"],
        service_build_url: env["BUILDKITE_BUILD_URL"],
        service_branch: env["BUILDKITE_BRANCH"],
      }
      if (pull_request = env["BUILDKITE_PULL_REQUEST"]) in ["false", nil] do
        ci_info
      else
        Map.put(ci_info, :service_pull_request, pull_request)
      end
    end

    @spec post_coveralls([atom], String.t, %{atom => String.t}, String.t) :: :ok
    def post_coveralls(mods, output, ci_info, url \\ "https://coveralls.io/api/v1/jobs") do
      IO.puts "post to coveralls"
      Application.ensure_all_started(:hackney)
      source = Coverex.Source.coveralls_data(mods)
      body = ci_info |> Map.put(:source_files, source) |> Poison.encode!
      filename = "./#{output}/coveralls.json"
      File.write(filename, body)
      response = send_http(url, filename, body)
      IO.puts("Response: #{inspect response}")
    end

    def send_http(url, filename, _body) do
      :hackney.post(url, [],
        {:multipart, [
          {:file, filename,
            {"form-data", [{"name", "json_file"}, {"filename", filename}]},
            [{"Content-Type", "application/json"}]
          }
        ]},
        [:with_body])
    end

    def write_html_file(mod, output) do
      {entries, source} = Coverex.Source.analyze_to_html(mod)
      {:ok, s} = StringIO.open(source)
      lines = Stream.zip(numbers(), IO.stream(s, :line)) |> Stream.map(fn({n, line}) ->
        case Map.get(entries, n, nil) do
          {count, anchor} -> {n, {encode_html(line), count, anchor}}
          nil -> {n, {encode_html(line), nil, nil}}
        end
      end) |> Enum.map(&(&1))

      # IO.inspect(lines)
      content = source_template(mod, lines)
      File.write("#{output}/#{mod}.html", content)
    end

    # all positive numbers
    defp numbers(), do: Stream.iterate(1, &(&1+1))

    def encode_html(s, acc \\ "")
    def encode_html("", acc), do: acc
    def encode_html(s, acc) do
      {first, rest} = String.next_grapheme(s)
      case first do
        ">" -> encode_html(rest, acc <> "&gt;")
        "<" -> encode_html(rest, acc <> "&lt;")
        "&" -> encode_html(rest, acc <> "&amp;")
        nil -> acc
        any -> encode_html(rest, acc <> any)
      end
    end

    def write_module_overview(modules, output) do
      mods = Enum.map(modules, fn({mod, v}) -> {module_link(mod), v} end)
      content = overview_template("Modules", mods)
      File.write("#{output}/modules.html", content)
    end

    def puts_module_overview(modules) do
      # mods = Enum.map(modules, fn({mod, v}) -> {module_link(mod), v} end)
      content = overview_text_template(modules)
      IO.puts content
    end

    def write_function_overview(functions, output) do
      funs = Enum.map(functions, fn({{m,f,a}, v}) -> {module_link(m, f, a), v} end)
      content = overview_template("Functions", funs)
      File.write("#{output}/functions.html", content)
    end

    defp module_link(mod), do: "<a href=\"#{mod}.html\">#{mod}</a>"
    defp module_link(m, f, a), do: "<a href=\"#{m}.html##{m}.#{f}.#{a}\">#{m}.#{f}/#{a}</a>"

    def module_anchor({m, f, a}), do: "<a name=\"##{m}.#{f}.#{a}\"></a>"
    def module_anchor(m), do: "<a name=\"##{m}\"></a>"

    def cover_class(nil), do: "irrelevant"
    def cover_class(0), do: "not_covered"
    def cover_class(_n), do: "covered"

    @doc """
    Returns detailed coverage data `{mod, mf}` for all modules from the `:cover` application.
    The special functions `__info__` and `__struct__` are filtered out of
    the list of covered functions.

    ## The `mod` data
    The `mod` data is a list of pairs: `{modulename, {no of covered lines, no of uncovered lines}}`

    ## The `mf` data
    The `mf` data is list of pairs: `{{m, f, a}, {no of covered lines, no of uncovered lines}}`

    """
    @spec coverage_data([atom]) :: {mod_cover, fun_cover}
    def coverage_data(all_modules) do
      modules = Enum.map(all_modules, fn(mod) ->
        {:ok, {m, {cov, noncov}}} = :cover.analyse(mod, :coverage, :module)
        {m, {cov, noncov}}
      end) |> Enum.sort
      mfunc = Enum.flat_map(all_modules, fn(mod) ->
        {:ok, funcs} = :cover.analyse(mod, :coverage, :function)
        funcs
      end)
      |> Enum.reject(fn {{_m, f, _}, _}
          when f in [:__info__, :__struct__,
                     :__behaviour_info__, :__protocol__]-> true
                        _ -> false end)
      |> Enum.sort
      {modules, mfunc}
    end

    ## Generate templating functions via EEx, borrowd from ex_doc
    templates = [
      overview_text_template: [:entries],
      overview_entry_text_template: [:entry, :cov, :uncov, :ratio],
      overview_template: [:title, :entries],
      overview_entry_template: [:entry, :cov, :uncov, :ratio],
      source_template: [:title, :lines],
      source_line_template: [:number, :count, :source, :anchor]
    ]
    Enum.each templates, fn({ name, args }) ->
      filename = Path.expand("templates/#{name}.eex", __DIR__)
      EEx.function_from_file :def, name, filename, args
    end

    # generates asset files
    defp generate_assets(output) do
      Enum.each assets(), fn({ pattern, dir }) ->
        output = "#{output}/#{dir}"
        File.mkdir output

        Enum.map Path.wildcard(pattern), fn(file) ->
          base = Path.basename(file)
          File.copy file, "#{output}/#{base}"
        end
      end
    end
    # assets are javascript, css and gif resources
    defp assets do
      [ { templates_path("css/*.css"), "css" },
        { templates_path("js/*.js"), "js" },
        { templates_path("css/*.gif"), "css" },
      ]
    end
    defp templates_path(other), do: Path.expand("templates/#{other}", __DIR__)

end
