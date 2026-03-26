require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires an email address" do
      user = User.new(password: "securepassword1", password_confirmation: "securepassword1")
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to include("can't be blank")
    end

    it "requires a unique email address" do
      User.create!(email_address: "taken@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      user = User.new(email_address: "taken@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to include("has already been taken")
    end

    it "requires a valid email format" do
      user = User.new(email_address: "not-an-email", password: "securepassword1", password_confirmation: "securepassword1")
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to include("is invalid")
    end

    it "requires a password of at least 12 characters" do
      user = User.new(email_address: "test@example.com", password: "short", password_confirmation: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("is too short (minimum is 12 characters)")
    end

    it "accepts a password of 12 or more characters" do
      user = User.new(email_address: "test@example.com", password: "securepassw1", password_confirmation: "securepassw1")
      expect(user).to be_valid
    end
  end

  describe "email normalization" do
    it "strips whitespace and downcases the email" do
      user = User.create!(email_address: "  Test@Example.COM  ", password: "securepassword1", password_confirmation: "securepassword1")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "associations" do
    it "destroys associated sessions when destroyed" do
      user = User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

      expect { user.destroy }.to change(Session, :count).by(-1)
    end
  end

  describe "#editor_for?" do
    let(:user) { User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1") }
    let(:team) { Team.create!(name: "Test Team") }

    it "returns true when the user has an editor membership for the team" do
      Membership.create!(user: user, team: team, role: "editor")
      expect(user.editor_for?(team)).to be true
    end

    it "returns false when the user has a member membership for the team" do
      Membership.create!(user: user, team: team, role: "member")
      expect(user.editor_for?(team)).to be false
    end

    it "returns false when the user has no membership for the team" do
      expect(user.editor_for?(team)).to be false
    end

    it "checks the role per-team" do
      other_team = Team.create!(name: "Other Team")
      Membership.create!(user: user, team: team, role: "editor")
      Membership.create!(user: user, team: other_team, role: "member")

      expect(user.editor_for?(team)).to be true
      expect(user.editor_for?(other_team)).to be false
    end

    it "returns false when team is nil" do
      expect(user.editor_for?(nil)).to be false
    end
  end
end
