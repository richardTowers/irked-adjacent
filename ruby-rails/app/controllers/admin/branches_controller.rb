module Admin
  class BranchesController < ApplicationController
    def index
      @branches = Branch.order(
        Arel.sql("CASE WHEN name = 'main' THEN 0 WHEN name = 'published' THEN 1 ELSE 2 END, name ASC")
      )
    end

    def new
      @branch = Branch.new
    end

    def create
      @branch = Branch.new(branch_params)

      if @branch.save
        redirect_to admin_branches_path, notice: "Branch was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @branch = Branch.find(params[:id])

      if @branch.protected?
        redirect_to admin_branches_path, alert: "Cannot delete a protected branch.", status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        Version.where(branch_id: @branch.id).delete_all
        @branch.destroy!
      end

      session.delete(:current_branch_id) if session[:current_branch_id] == @branch.id
      redirect_to admin_branches_path, notice: "Branch was successfully deleted."
    end

    def switch
      branch = Branch.find(params[:branch_id])
      session[:current_branch_id] = branch.id
      redirect_to request.referer || admin_content_index_path
    end

    private

    def branch_params
      params.require(:branch).permit(:name)
    end
  end
end
