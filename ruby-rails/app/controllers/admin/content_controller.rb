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
    end

    def create
      @node = Node.new(node_params)

      unless Current.user.teams.exists?(id: @node.team_id)
        @node.errors.add(:team_id, "is not a team you belong to")
        return render :new, status: :unprocessable_entity
      end

      if @node.save
        redirect_to admin_content_path(@node), notice: "Node was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @node.update(update_params)
        redirect_to admin_content_path(@node), notice: "Node was successfully updated."
      else
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

    def node_params
      params.require(:node).permit(:title, :slug, :body, :published, :team_id)
    end

    def update_params
      params.require(:node).permit(:title, :slug, :body, :published)
    end
  end
end
