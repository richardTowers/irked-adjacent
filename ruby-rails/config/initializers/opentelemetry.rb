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
end
