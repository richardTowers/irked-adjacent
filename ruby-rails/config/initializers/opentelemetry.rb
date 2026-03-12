# frozen_string_literal: true

return unless ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"
require "opentelemetry/metrics/sdk"
require "opentelemetry/exporter/otlp/metrics"
require "opentelemetry/logs/sdk"
require "opentelemetry/exporter/otlp/logs"

endpoint = ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT")

# Traces — hooks into ActiveSupport::Notifications via instrumentation-all
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "ruby-rails")
  c.use_all(
    "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: ["/up"] }
  )
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: endpoint)
    )
  )
end

# Metrics
OpenTelemetry::Metrics::SDK.configure do |c|
  c.add_metric_reader(
    OpenTelemetry::Metrics::SDK::Export::PeriodicExportingMetricReader.new(
      OpenTelemetry::Exporter::OTLP::Metrics::Exporter.new(endpoint: endpoint),
      export_interval_millis: 30_000
    )
  )
end

# Logs — receives Rails.event structured events via OtlpEventSubscriber
OpenTelemetry::Logs::SDK.configure do |c|
  c.add_log_record_processor(
    OpenTelemetry::Logs::SDK::Export::BatchLogRecordProcessor.new(
      OpenTelemetry::Exporter::OTLP::Logs::Exporter.new(endpoint: endpoint)
    )
  )
end

# Register the subscriber — Rails.event.notify(...) flows here → Loki
Rails.event.subscribe(OtlpEventSubscriber.new)
