require 'rails_helper'

RSpec.describe Membership, type: :model do
  let(:user) { User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1") }
  let(:team) { Team.create!(name: "Test Team") }

  describe "validations" do
    it "is valid with a user, team, and default role" do
      membership = Membership.new(user: user, team: team)
      expect(membership).to be_valid
    end

    it "defaults role to member" do
      membership = Membership.create!(user: user, team: team)
      expect(membership.role).to eq("member")
    end

    it "requires a user" do
      membership = Membership.new(team: team)
      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to include("must exist")
    end

    it "requires a team" do
      membership = Membership.new(user: user)
      expect(membership).not_to be_valid
      expect(membership.errors[:team]).to include("must exist")
    end

    it "accepts the editor role" do
      membership = Membership.new(user: user, team: team, role: "editor")
      expect(membership).to be_valid
    end

    it "requires a valid role" do
      membership = Membership.new(user: user, team: team, role: "admin")
      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to include("is not included in the list")
    end

    it "rejects a blank role" do
      membership = Membership.new(user: user, team: team, role: "")
      expect(membership).not_to be_valid
    end

    it "enforces uniqueness of user within a team" do
      Membership.create!(user: user, team: team)
      duplicate = Membership.new(user: user, team: team)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end

    it "allows the same user in different teams" do
      other_team = Team.create!(name: "Other Team")
      Membership.create!(user: user, team: team)
      membership = Membership.new(user: user, team: other_team)
      expect(membership).to be_valid
    end

    it "allows different users in the same team" do
      other_user = User.create!(email_address: "other@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      Membership.create!(user: user, team: team)
      membership = Membership.new(user: other_user, team: team)
      expect(membership).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a user" do
      membership = Membership.create!(user: user, team: team)
      expect(membership.user).to eq(user)
    end

    it "belongs to a team" do
      membership = Membership.create!(user: user, team: team)
      expect(membership.team).to eq(team)
    end
  end

  describe "cascading deletes" do
    it "is destroyed when its user is destroyed" do
      Membership.create!(user: user, team: team)
      expect { user.destroy }.to change(Membership, :count).by(-1)
    end

    it "is destroyed when its team is destroyed" do
      Membership.create!(user: user, team: team)
      expect { team.destroy }.to change(Membership, :count).by(-1)
    end
  end

  describe "database constraints" do
    it "enforces compound unique index on user_id and team_id" do
      Membership.create!(user: user, team: team)
      duplicate = Membership.new(user: user, team: team)
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces NOT NULL on role" do
      membership = Membership.new(user: user, team: team)
      membership.role = nil
      expect {
        membership.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "defaults role to member at the database level" do
      membership = Membership.new(user: user, team: team)
      membership.save!
      membership.reload
      expect(membership.role).to eq("member")
    end
  end
end
