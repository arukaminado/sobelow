defmodule Sobelow.Config.CSP do
  @moduledoc """
  # Missing Content-Security-Policy

  Content-Security-Policy is an HTTP header that helps mitigate
  a number of attacks, including Cross-Site Scripting.

  Read more about CSP here:
  https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP

  Missing Content-Security-Policy is flagged by `sobelow` when
  a pipeline implements the `:put_secure_browser_headers` plug,
  but does not provide a Content-Security-Policy header in the
  custom headers map.

  Documentation on the `put_secure_browser_headers` plug function
  can be found here:
  https://hexdocs.pm/phoenix/Phoenix.Controller.html#put_secure_browser_headers/2

  Content-Security-Policy checks can be ignored with the following command:

      $ mix sobelow -i Config.CSP
  """
  alias Sobelow.Config
  use Sobelow.Finding
  @finding_type "Config.CSP: Missing Content-Security-Policy"

  def run(router, _) do
    meta_file = Parse.ast(router) |> Parse.get_meta_funs()
    finding = Finding.init(@finding_type, Utils.normalize_path(router))

    Config.get_pipelines(router)
    |> Enum.map(&check_vuln_pipeline(&1, meta_file))
    |> Enum.each(&maybe_add_finding(&1, finding))
  end

  def check_vuln_pipeline({:pipeline, _, [_name, [do: block]]} = pipeline, meta_file) do
    {vuln?, conf, plug} =
      Config.get_plug_list(block)
      |> Enum.find(&is_header_plug?/1)
      |> missing_csp_status(meta_file)

    {vuln?, conf, plug, pipeline}
  end

  defp is_header_plug?({:plug, _, [:put_secure_browser_headers]}), do: true
  defp is_header_plug?({:plug, _, [:put_secure_browser_headers, _]}), do: true
  defp is_header_plug?(_), do: false

  defp missing_csp_status({_, _, [:put_secure_browser_headers]} = plug, _),
    do: {true, :high, plug}

  defp missing_csp_status({_, _, [:put_secure_browser_headers, {:%{}, _, opts}]} = plug, _) do
    {!include_csp?(opts), :high, plug}
  end

  defp missing_csp_status({_, _, [:put_secure_browser_headers, {:@, _, opts}]} = plug, meta_file) do
    [{attr, _, nil} | _] = opts

    has_csp? =
      Enum.find_value(meta_file.module_attrs, fn mod_attr ->
        case mod_attr do
          {^attr, _, [{:%{}, _, definition}]} -> definition
          _ -> false
        end
      end)
      |> include_csp?()

    {!has_csp?, :high, plug}
  end

  defp missing_csp_status({_, _, [:put_secure_browser_headers, _]} = plug, _),
    do: {true, :low, plug}

  defp missing_csp_status(plug, _), do: {false, :high, plug}

  defp include_csp?(nil), do: false

  defp include_csp?(headers) do
    Enum.any?(headers, fn
      {key, _} when is_binary(key) ->
        String.downcase(key) == "content-security-policy"

      _ ->
        false
    end)
  end

  defp maybe_add_finding({true, confidence, plug, {:pipeline, _, [pipeline_name, _]} = pipeline}, finding) do
    %{
      finding
      | vuln_source: :put_secure_browser_headers,
        vuln_line_no: Parse.get_fun_line(plug),
        fun_source: pipeline,
        fun_name: pipeline_name,
        confidence: confidence
    }
    |> add_finding()
  end

  defp maybe_add_finding(_, _), do: nil

  defp add_finding(%Finding{} = finding) do
    file_header = "File: #{finding.filename}"
    pipeline_header = "Pipeline: #{finding.fun_name}"
    line_header = "Line: #{finding.vuln_line_no}"

    case Sobelow.format() do
      "json" ->
        json_finding = [
          type: finding.type,
          file: finding.filename,
          pipeline: finding.fun_name,
          line: finding.vuln_line_no
        ]

        Sobelow.log_finding(json_finding, finding.confidence)

      "txt" ->
        Sobelow.log_finding(finding.type, finding.confidence)

        Print.print_custom_finding_metadata(
          finding,
          [file_header, pipeline_header, line_header]
        )

      "compact" ->
        Print.log_compact_finding(finding.type, finding.confidence)

      _ ->
        Sobelow.log_finding(finding.type, finding.confidence)
    end
  end
end
