module Admin
  class ContentTypesController < ApplicationController
    before_action :set_user_teams
    before_action :set_content_type, only: %i[show edit update destroy]
    before_action :require_editor_role, only: %i[new create edit update destroy]

    def index
      @content_types = authorized_content_types.includes(:team, :field_definitions).order(:name)
    end

    def show
    end

    def new
      @content_type = ContentType.new
    end

    def create
      @content_type = ContentType.new(content_type_params)

      unless Current.user.editor_for?(Team.find_by(id: @content_type.team_id))
        @content_type.errors.add(:team_id, "is not a team you belong to or you lack the editor role")
        return render :new, status: :unprocessable_entity
      end

      if @content_type.save
        redirect_to admin_content_type_path(@content_type.slug), notice: "Content type was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @content_type.update(update_params)
        redirect_to admin_content_type_path(@content_type.slug), notice: "Content type was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @content_type.nodes.any?
        redirect_to admin_content_type_path(@content_type.slug), alert: "Cannot delete a content type that has nodes. Delete or reassign the nodes first."
      else
        @content_type.destroy
        redirect_to admin_content_types_path, notice: "Content type was successfully deleted."
      end
    end

    private

    def set_user_teams
      @user_teams = Current.user.teams
    end

    def set_content_type
      @content_type = authorized_content_types.find_by!(slug: params[:slug])
    end

    def authorized_content_types
      ContentType.where(team: @user_teams)
    end

    def content_type_params
      params.require(:content_type).permit(:name, :slug, :description, :team_id)
    end

    def update_params
      params.require(:content_type).permit(:name, :slug, :description)
    end

    def require_editor_role
      team = @content_type&.team
      team ||= Current.user.teams.find_by(id: params.dig(:content_type, :team_id)) if params[:content_type]

      if team
        render_forbidden unless Current.user.editor_for?(team)
      else
        render_forbidden unless Current.user.memberships.exists?(role: "editor")
      end
    end
  end
end
