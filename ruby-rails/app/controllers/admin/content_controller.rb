module Admin
  class ContentController < ApplicationController
    def index
      @nodes = Node.order(updated_at: :desc)
    end

    def show
      @node = Node.find(params[:id])
    end
  end
end
