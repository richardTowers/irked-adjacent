# frozen_string_literal: true

class OtlpEventSubscriber
  def emit(event)
    logger_provider = OpenTelemetry::Logs::SDK.logger_provider
    logger = logger_provider.logger(name: "rails.event", version: Rails.version)

    logger.on_emit(
      severity_number: OpenTelemetry::Logs::SeverityNumber::INFO,
      severity_text: "INFO",
      timestamp: Time.at(0, event[:timestamp], :nanosecond),
      body: event[:name],
      attributes: flatten_event(event)
    )
  end

  private

  def flatten_event(event)
    attrs = {}
    attrs["event.name"] = event[:name]
    attrs.merge!(event[:context].transform_keys { |k| "context.#{k}" }) if event[:context]
    attrs.merge!(event[:tags].transform_keys { |k| "tag.#{k}" }) if event[:tags]
    if event[:payload].is_a?(Hash)
      event[:payload].each { |k, v| attrs["payload.#{k}"] = v.to_s }
    end
    if (loc = event[:source_location])
      attrs["code.filepath"] = loc[:filepath]
      attrs["code.lineno"] = loc[:lineno].to_s
      attrs["code.function"] = loc[:label]
    end
    attrs
  end
end
