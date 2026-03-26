module Admin
  class ContentController < ApplicationController
    before_action :set_user_teams
    before_action :set_node, only: %i[show edit update destroy]

    def index
      @nodes = authorized_nodes.order(updated_at: :desc)
    end

    def show
    end

    def new
      @node = Node.new
      load_content_type_from_param
      load_form_data
    end

    def create
      @node = Node.new(node_params)

      unless Current.user.teams.exists?(id: @node.team_id)
        @node.errors.add(:team_id, "is not a team you belong to")
        load_form_data
        return render :new, status: :unprocessable_entity
      end

      if @node.save
        redirect_to admin_content_path(@node), notice: "Node was successfully created."
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_form_data
    end

    def update
      if @node.update(update_params)
        redirect_to admin_content_path(@node), notice: "Node was successfully updated."
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @node.destroy
      redirect_to admin_content_index_path, notice: "Node was successfully deleted."
    end

    private

    def set_user_teams
      @user_teams = Current.user.teams
    end

    def set_node
      @node = authorized_nodes.find(params[:id])
    end

    def authorized_nodes
      Node.where(team: @user_teams)
    end

    def load_content_type_from_param
      if params[:content_type_id].present?
        ct = ContentType.where(team: @user_teams).find_by(id: params[:content_type_id])
        @node.content_type = ct if ct
      end

      # Pre-select if team has exactly one content type
      if @node.content_type.nil?
        team_content_types = ContentType.where(team: @user_teams)
        @node.content_type = team_content_types.first if team_content_types.count == 1
      end
    end

    def load_form_data
      @field_definitions = if @node.content_type
        @node.content_type.field_definitions.order(:position)
      else
        []
      end

      @reference_nodes = accessible_reference_nodes
    end

    def accessible_reference_nodes
      Node.where(team: @user_teams).includes(:content_type).order(:title)
    end

    def node_params
      permitted = params.require(:node).permit(:title, :slug, :published, :team_id, :content_type_id)
      merge_fields_params(permitted, content_type_for_create)
    end

    def update_params
      permitted = params.require(:node).permit(:title, :slug, :published)
      merge_fields_params(permitted, @node.content_type)
    end

    def content_type_for_create
      ct_id = params.dig(:node, :content_type_id)
      ContentType.find_by(id: ct_id) if ct_id.present?
    end

    def merge_fields_params(permitted, content_type)
      return permitted unless content_type

      field_defs = content_type.field_definitions
      field_keys = field_defs.pluck(:api_key)
      raw_fields = params.dig(:node, :fields)&.permit(field_keys)&.to_h || {}

      # Cast field values to appropriate types
      fields = {}
      field_defs.each do |fd|
        key = fd.api_key
        if fd.field_type == "boolean"
          # Hidden field trick: browsers don't submit unchecked checkboxes,
          # but the hidden field sends "false". Convert to actual boolean.
          fields[key] = ActiveModel::Type::Boolean.new.cast(raw_fields[key]) || false
        elsif raw_fields.key?(key)
          value = raw_fields[key]
          fields[key] = cast_field_value(value, fd.field_type)
        end
      end

      permitted.merge(fields: fields)
    end

    def cast_field_value(value, field_type)
      case field_type
      when "integer"
        value.present? ? value.to_i : nil
      when "decimal"
        value.present? ? value.to_f : nil
      when "reference"
        value.present? ? value.to_i : nil
      else
        value
      end
    end
  end
end
