require "rails_helper"

RSpec.describe "Admin::Teams::Members", type: :request do
  let(:user) { create_and_sign_in_user }
  let(:team) { Team.create!(name: "Test Team") }

  before do
    Membership.create!(user: user, team: team, role: "editor")
  end

  describe "POST /admin/teams/:team_id/members" do
    let!(:other_user) { User.create!(email_address: "other@example.com", password: "password123!", password_confirmation: "password123!") }

    it "adds a member with the default member role" do
      post admin_team_members_path(team), params: { email_address: other_user.email_address }

      membership = team.memberships.find_by(user: other_user)
      expect(membership.role).to eq("member")
    end

    it "adds a member with the editor role when specified" do
      post admin_team_members_path(team), params: { email_address: other_user.email_address, role: "editor" }

      membership = team.memberships.find_by(user: other_user)
      expect(membership.role).to eq("editor")
    end

    it "ignores invalid role values and defaults to member" do
      post admin_team_members_path(team), params: { email_address: other_user.email_address, role: "admin" }

      membership = team.memberships.find_by(user: other_user)
      expect(membership.role).to eq("member")
    end
  end

  describe "PATCH /admin/teams/:team_id/members/:id" do
    let!(:other_user) { User.create!(email_address: "other@example.com", password: "password123!", password_confirmation: "password123!") }
    let!(:membership) { Membership.create!(user: other_user, team: team, role: "member") }

    it "updates the member's role" do
      patch admin_team_member_path(team, membership), params: { role: "editor" }

      expect(membership.reload.role).to eq("editor")
      expect(response).to redirect_to(admin_team_path(team))
    end

    it "can downgrade a role from editor to member" do
      membership.update!(role: "editor")

      patch admin_team_member_path(team, membership), params: { role: "member" }

      expect(membership.reload.role).to eq("member")
    end

    it "rejects invalid role values" do
      patch admin_team_member_path(team, membership), params: { role: "admin" }

      expect(membership.reload.role).to eq("member")
      expect(response).to redirect_to(admin_team_path(team))
      follow_redirect!
      expect(response.body).to include("Invalid role")
    end
  end

  describe "role selector in team show page" do
    it "displays a role selector for each member" do
      get admin_team_path(team)

      expect(response.body).to include("Member")
      expect(response.body).to include("Editor")
    end

    it "displays role descriptions in the add member form" do
      get admin_team_path(team)

      expect(response.body).to include("Can create and manage content.")
      expect(response.body).to include("Can create and manage content, and configure content types.")
    end

    it "has a role fieldset with radio buttons" do
      get admin_team_path(team)

      expect(response.body).to include("<legend>Role</legend>")
      expect(response.body).to include('value="member"')
      expect(response.body).to include('value="editor"')
    end
  end
end
