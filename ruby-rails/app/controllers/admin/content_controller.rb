module Admin
  class ContentController < ApplicationController
    def index
      @nodes = Node.order(updated_at: :desc)
    end

    def show
      @node = Node.find(params[:id])
    end

    def new
      @node = Node.new
    end

    def create
      @node = Node.new(node_params)

      if @node.save
        redirect_to admin_content_path(@node), notice: "Node was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def node_params
      params.require(:node).permit(:title, :slug, :body, :published)
    end
  end
end
