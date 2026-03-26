class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  around_action :set_event_context

  private

  def render_not_found
    render plain: "Not Found", status: :not_found
  end

  def render_forbidden
    render "errors/forbidden", status: :forbidden, layout: "application"
  end

  def set_event_context
    trace_id = if defined?(OpenTelemetry)
      span = OpenTelemetry::Trace.current_span
      span.context.valid? ? span.context.hex_trace_id : nil
    end

    Rails.event.set_context(
      request_id: request.request_id,
      trace_id: trace_id
    )
    yield
  end
end
