module Admin
  class ContentController < ApplicationController
    def index
      @nodes = Node.order(updated_at: :desc)
      @main_branch = Branch.find_by!(name: "main")
      @published_branch = Branch.find_by!(name: "published")
    end

    def show
      @node = Node.find(params[:id])
      @published_branch = Branch.find_by!(name: "published")
      @main_branch = Branch.find_by!(name: "main")

      @current_version = Version.current_for(@node, current_branch)
      @fallback = false
      if @current_version.nil? && current_branch != @main_branch
        @current_version = Version.current_for(@node, @main_branch)
        @fallback = true
      end

      @latest_committed = @node.versions.committed.where(branch: current_branch).order(committed_at: :desc).first
      @latest_published = @node.versions.committed.where(branch: @published_branch).order(committed_at: :desc).first
      @has_uncommitted = @node.versions.uncommitted.where(branch: current_branch).exists?
    end

    def new
      @node = Node.new
      @version = Version.new
    end

    def create
      begin
        @node, @version = Node.create_with_version(
          title: create_params[:title],
          slug: create_params[:slug],
          body: create_params[:body],
          branch: current_branch
        )
        redirect_to admin_content_path(@node), notice: "Node was successfully created."
      rescue ActiveRecord::RecordInvalid => e
        @node = e.record.is_a?(Node) ? e.record : Node.new(slug: create_params[:slug])
        @version = e.record.is_a?(Version) ? e.record : Version.new(title: create_params[:title], body: create_params[:body])
        # Ensure version errors are populated even when the node failed first
        @version.valid? unless @version.errors.any?
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @node = Node.find(params[:id])
      @main_branch = Branch.find_by!(name: "main")

      @current_version = Version.current_for(@node, current_branch)
      if @current_version.nil? && current_branch != @main_branch
        @current_version = Version.current_for(@node, @main_branch)
      end

      @version = Version.new(title: @current_version&.title, body: @current_version&.body)
    end

    def update
      @node = Node.find(params[:id])
      @main_branch = Branch.find_by!(name: "main")

      @version = Version.uncommitted.find_by(node: @node, branch: current_branch)

      if @version
        @version.assign_attributes(update_params)
      else
        latest_committed = Version.committed
                                   .where(node: @node, branch: current_branch)
                                   .order(committed_at: :desc)
                                   .first

        if latest_committed
          # Existing committed version on this branch — create new draft with parent
          @version = Version.new(
            node: @node,
            branch: current_branch,
            parent_version: latest_committed,
            **update_params
          )
        else
          # No version on this branch — fork from main
          source = Version.committed
                          .where(node: @node, branch: @main_branch)
                          .order(committed_at: :desc)
                          .first
          @version = Version.new(
            node: @node,
            branch: current_branch,
            source_version: source,
            **update_params
          )
        end
      end

      if @version.save
        redirect_to admin_content_path(@node), notice: "Draft was successfully saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def commit
      @node = Node.find(params[:id])

      @current_version = Version.uncommitted.find_by(node: @node, branch: current_branch)

      unless @current_version
        redirect_to admin_content_path(@node), alert: "No uncommitted changes to commit."
        return
      end

      message = params.dig(:commit, :commit_message).to_s

      if message.blank?
        redirect_to admin_content_path(@node), alert: "Commit message can't be blank."
        return
      end

      @current_version.commit!(message)
      redirect_to admin_content_path(@node), notice: "Version was successfully committed."
    end

    def publish
      @node = Node.find(params[:id])

      latest_committed = @node.versions.committed.where(branch: current_branch).order(committed_at: :desc).first

      unless latest_committed
        redirect_to admin_content_path(@node), alert: "No committed version to publish."
        return
      end

      published_branch = Branch.find_by!(name: "published")
      latest_published = @node.versions.committed.where(branch: published_branch).order(committed_at: :desc).first

      if latest_published && latest_published.source_version_id == latest_committed.id
        redirect_to admin_content_path(@node), alert: "Published version is already up to date."
        return
      end

      Version.publish!(latest_committed)
      redirect_to admin_content_path(@node), notice: "Node was successfully published."
    end

    def destroy
      @node = Node.find(params[:id])
      @node.destroy
      redirect_to admin_content_index_path, notice: "Node was successfully deleted."
    end

    private

    def create_params
      params.require(:node).permit(:title, :slug, :body)
    end

    def update_params
      params.require(:node).permit(:title, :body)
    end
  end
end
