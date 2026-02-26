module Public
  class ContentController < ApplicationController
    layout "public"

    def show
      @node = Node.find_by!(slug: params[:slug])
      @published_branch = Branch.find_by!(name: "published")
      @version = Version.current_for(@node, @published_branch)

      raise ActiveRecord::RecordNotFound unless @version
    end
  end
end
