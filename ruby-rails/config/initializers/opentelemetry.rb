# frozen_string_literal: true

return unless ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?

require "opentelemetry-sdk"
require "opentelemetry-exporter-otlp"
require "opentelemetry/instrumentation/all"
require "opentelemetry-metrics-sdk"
require "opentelemetry-exporter-otlp-metrics"
require "opentelemetry-logs-sdk"
require "opentelemetry-exporter-otlp-logs"

# All three exporters read OTEL_EXPORTER_OTLP_ENDPOINT from env
# and append the correct signal path (/v1/traces, /v1/metrics, /v1/logs).
# Passing endpoint: explicitly would override the path, breaking routing.

# Traces + Logs — configured together via SDK.configure
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "ruby-rails")
  c.use_all(
    "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: ["/up"] }
  )
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )
  c.add_log_record_processor(
    OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
      OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new
    )
  )
end

# Metrics — configured on the meter_provider after SDK.configure
OpenTelemetry.meter_provider.add_metric_reader(
  OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
    exporter: OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new,
    export_interval_millis: 30_000
  )
)

# Register the subscriber — Rails.event.notify(...) flows here → Loki
Rails.application.config.after_initialize do
  Rails.event.subscribe(OtlpEventSubscriber.new)

  # Application metrics via ActiveSupport::Notifications
  meter = OpenTelemetry.meter_provider.meter("rails.app")

  request_counter = meter.create_counter(
    "http.server.request.count", unit: "requests",
    description: "Total HTTP requests"
  )
  request_duration = meter.create_histogram(
    "http.server.request.duration", unit: "ms",
    description: "HTTP request duration"
  )
  db_duration = meter.create_histogram(
    "db.query.duration", unit: "ms",
    description: "Database query duration"
  )
  render_duration = meter.create_histogram(
    "view.render.duration", unit: "ms",
    description: "View template render duration"
  )

  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |event|
    attrs = {
      "http.method" => event.payload[:method],
      "controller" => event.payload[:controller],
      "action" => event.payload[:action],
      "http.status_code" => event.payload[:status].to_s
    }
    request_counter.add(1, attributes: attrs)
    request_duration.record(event.duration, attributes: attrs)
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
    operation = event.payload[:sql].to_s.split.first&.upcase
    next unless %w[SELECT INSERT UPDATE DELETE].include?(operation)
    db_duration.record(event.duration, attributes: { "db.operation" => operation })
  end

  ActiveSupport::Notifications.subscribe("render_template.action_view") do |event|
    template = event.payload[:identifier].to_s.sub(Rails.root.to_s + "/", "")
    render_duration.record(event.duration, attributes: { "template" => template })
  end
end
