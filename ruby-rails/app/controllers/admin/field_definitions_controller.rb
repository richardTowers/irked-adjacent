module Admin
  class FieldDefinitionsController < ApplicationController
    before_action :set_user_teams
    before_action :set_content_type
    before_action :set_field_definition, only: %i[update destroy]
    before_action :require_editor_role

    def create
      @field_definition = @content_type.field_definitions.build(field_definition_params)

      if @field_definition.save
        redirect_to admin_content_type_path(@content_type.slug), notice: "Field was successfully added."
      else
        @field_definition_form = @field_definition
        render "admin/content_types/show", status: :unprocessable_entity
      end
    end

    def update
      if @field_definition.update(field_definition_params)
        redirect_to admin_content_type_path(@content_type.slug), notice: "Field was successfully updated."
      else
        @editing_field = @field_definition
        render "admin/content_types/show", status: :unprocessable_entity
      end
    end

    def destroy
      @field_definition.destroy
      redirect_to admin_content_type_path(@content_type.slug), notice: "Field was successfully removed."
    end

    private

    def set_user_teams
      @user_teams = Current.user.teams
    end

    def set_content_type
      @content_type = ContentType.where(team: @user_teams).find_by!(slug: params[:content_type_slug])
    end

    def set_field_definition
      @field_definition = @content_type.field_definitions.find(params[:id])
    end

    def field_definition_params
      params.require(:field_definition).permit(:name, :api_key, :field_type, :required, :position)
    end

    def require_editor_role
      render_forbidden unless Current.user.editor_for?(@content_type.team)
    end
  end
end
