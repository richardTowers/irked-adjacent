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

    def edit
      @node = Node.find(params[:id])
    end

    def update
      @node = Node.find(params[:id])

      if @node.update(node_params)
        redirect_to admin_content_path(@node), notice: "Node was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @node = Node.find(params[:id])
      @node.destroy
      redirect_to admin_content_index_path, notice: "Node was successfully deleted."
    end

    private

    def node_params
      params.require(:node).permit(:title, :slug, :body, :published)
    end
  end
end
