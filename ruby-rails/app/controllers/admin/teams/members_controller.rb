module Admin
  module Teams
    class MembersController < ApplicationController
      before_action :set_team

      def create
        user = User.find_by(email_address: params[:email_address])

        if user.nil?
          redirect_to admin_team_path(@team), alert: "No user found with that email address."
        elsif @team.users.include?(user)
          redirect_to admin_team_path(@team), alert: "That user is already a member of this team."
        else
          @team.memberships.create!(user: user, role: "member")
          redirect_to admin_team_path(@team), notice: "Member was successfully added."
        end
      end

      def destroy
        membership = @team.memberships.find(params[:id])

        if @team.memberships.count == 1
          redirect_to admin_team_path(@team), alert: "Cannot remove the last member of a team."
        else
          membership.destroy
          redirect_to admin_team_path(@team), notice: "Member was successfully removed."
        end
      end

      private

      def set_team
        @team = Current.user.teams.find(params[:team_id])
      end
    end
  end
end
