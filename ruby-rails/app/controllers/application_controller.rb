class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_branch

  private

  def current_branch
    @current_branch ||= Branch.find_by(id: session[:current_branch_id]) || Branch.find_by!(name: "main")
  end

  def render_not_found
    render plain: "Not Found", status: :not_found
  end
end
