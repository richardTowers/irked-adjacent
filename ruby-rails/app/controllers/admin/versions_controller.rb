module Admin
  class VersionsController < ApplicationController
    def show
      @node = Node.find(params[:content_id])
      @version = @node.versions.find(params[:id])
    end

    def revert
      @node = Node.find(params[:content_id])
      @version = @node.versions.find(params[:id])

      if current_branch.name == "published"
        redirect_to admin_content_path(@node), alert: "Cannot revert on the published branch."
        return
      end

      uncommitted = @node.versions.uncommitted.find_by(branch: current_branch)

      if uncommitted && uncommitted.id == @version.id
        redirect_to admin_content_path(@node), alert: "Cannot revert to the current draft."
        return
      end

      if uncommitted
        uncommitted.update!(title: @version.title, body: @version.body)
      else
        latest_committed = @node.versions.committed
                                .where(branch: current_branch)
                                .order(committed_at: :desc)
                                .first

        Version.create!(
          node: @node,
          branch: current_branch,
          title: @version.title,
          body: @version.body,
          parent_version: latest_committed,
          source_version: @version.committed_at.present? ? @version : nil
        )
      end

      timestamp = @version.committed_at&.strftime("%-d %B %Y %H:%M") || "uncommitted draft"
      redirect_to admin_content_path(@node), notice: "Reverted to version from #{timestamp}."
    end
  end
end
