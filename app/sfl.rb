class Sfl < Roda
  # Routing
  plugin :autoload_hash_branches
  autoload_hash_branch_dir("./app/routes")
  plugin :all_verbs
  plugin :not_found

  # Request / Response
  plugin :halt
  plugin :json
  plugin :error_handler
  plugin :exception_page
  plugin :caching
  plugin :cookies
  plugin :default_headers
  plugin :content_security_policy do |csp|
    # csp.default_src :none
    # csp.img_src :self
    # csp.style_src :self
    # csp.script_src :self
    # csp.font_src :self
    # csp.form_action :self
    # csp.base_uri :none
    # csp.frame_ancestors :none
    # csp.block_all_mixed_content
  end

  # CSRF Protection
  plugin :route_csrf

  # Other
  plugin :common_logger, Providers::Logger.get
  plugin :json_parser
  plugin :sessions, secret: Config.get[:secret]

  CORS_HEADERS = {
    "access-control-allow-methods" => "GET, POST, OPTIONS",
    "access-control-allow-headers" => "content-type",
  }.freeze

  def config = @config ||= Config.get
  def ctx = Providers::Engine.get

  route do |r|
    apply_cors(r)
    r.halt 204 if r.request_method == "OPTIONS"

    r.hash_branches

    r.root do
      { message: "hello world" }
    end
  end

  error do |e|
    if Config.not_production?
      puts e
      next exception_page(e, css_file: "/public/exception_page.css")
    end

    handle_error(e)
  end

  not_found do
    { error: "Not Found", path: request.path_info }
  end

  private

  # Ported from the old SFL::API::Server#with_cors/#preflight — allowlist
  # origin echo, no wildcard.
  def apply_cors(r)
    origin = r.env["HTTP_ORIGIN"]
    return unless origin && Providers::Engine.cors_origins.include?(origin)

    CORS_HEADERS.each { |k, v| response[k] = v }
    response["access-control-allow-origin"] = origin
  end

  def handle_error(e)
    if e.is_a?(ArgumentError)
      response.status = 400
      return { error: e.message }
    end

    request_id = SecureRandom.uuid
    warn "[ERROR] API #{e.class} request_id=#{request_id}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
    response.status = 500
    body = { error: "Internal Server Error", request_id: }
    body[:message] = e.message if Providers::Engine.debug_errors?
    body
  end

  # RetrievalFilters attribute — shared by /retrieve (POST body) and
  # /clauses (query params).
  def build_retrieval_filters(raw)
    f = symbolize_keys(raw)
    SFL::Core::Types::RetrievalFilters.new(
      **{
        mood: presence(f[:mood]),
        process_type: presence(f[:process_type]),
        source_type: presence(f[:source_type]),
        min_modality: numeric(f[:min_modality]),
        max_modality: numeric(f[:max_modality]),
        min_tenor: numeric(f[:min_tenor]),
        max_tenor: numeric(f[:max_tenor]),
      }.compact
    )
  end

  def presence(value)
    value.to_s.strip.empty? ? nil : value
  end

  def numeric(value)
    (value.nil? || value.to_s.strip.empty?) ? nil : value.to_f
  end

  def symbolize_keys(hash)
    hash.transform_keys(&:to_sym)
  end
end
