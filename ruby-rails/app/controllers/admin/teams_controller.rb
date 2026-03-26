module Admin
  class TeamsController < ApplicationController
    before_action :set_team, only: [:show, :edit, :update, :destroy]

    def index
      @teams = Current.user.teams.order(:name)
    end

    def show
    end

    def new
      @team = Team.new
    end

    def create
      @team = Team.new(team_params)

      if @team.save
        @team.memberships.create!(user: Current.user, role: "member")
        redirect_to admin_team_path(@team), notice: "Team was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @team.update(team_params)
        redirect_to admin_team_path(@team), notice: "Team was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @team.nodes.any?
        redirect_to admin_team_path(@team), alert: "Cannot delete a team that still has content. Reassign or delete the team's nodes first."
      else
        @team.destroy
        redirect_to admin_teams_path, notice: "Team was successfully deleted."
      end
    end

    private

    def set_team
      @team = Current.user.teams.find(params[:id])
    end

    def team_params
      params.require(:team).permit(:name, :slug)
    end
  end
end
