require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) do
    User.create!(
      email_address: "user@example.com",
      password: "securepassword1",
      password_confirmation: "securepassword1"
    )
  end

  describe "GET /session/new" do
    it "returns 200 and renders the sign-in form" do
      get new_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
      expect(response.body).to include("email_address")
      expect(response.body).to include("password")
    end

    it "includes a link to forgot password" do
      get new_session_path

      expect(response.body).to include("Forgot password?")
    end

    it "includes a link to sign up" do
      get new_session_path

      expect(response.body).to include("Sign up")
    end
  end

  describe "POST /session" do
    context "with valid credentials" do
      it "signs in and redirects to root" do
        post session_path, params: { email_address: "user@example.com", password: "securepassword1" }

        expect(response).to redirect_to(root_url)
      end

      it "sets a session cookie" do
        post session_path, params: { email_address: "user@example.com", password: "securepassword1" }

        expect(cookies[:session_id]).to be_present
      end

      it "creates a session record" do
        expect {
          post session_path, params: { email_address: "user@example.com", password: "securepassword1" }
        }.to change(Session, :count).by(1)
      end
    end

    context "with invalid credentials" do
      it "redirects to sign-in with an alert" do
        post session_path, params: { email_address: "user@example.com", password: "wrongpassword1" }

        expect(response).to redirect_to(new_session_path)
        follow_redirect!
        expect(response.body).to include("Try another email address or password.")
      end
    end

    context "with non-existent email" do
      it "redirects to sign-in with an alert" do
        post session_path, params: { email_address: "nobody@example.com", password: "securepassword1" }

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "DELETE /session" do
    before do
      post session_path, params: { email_address: "user@example.com", password: "securepassword1" }
    end

    it "signs out and redirects to sign-in page" do
      delete session_path

      expect(response).to redirect_to(new_session_path)
    end

    it "destroys the session record" do
      expect {
        delete session_path
      }.to change(Session, :count).by(-1)
    end
  end

  describe "authentication requirement" do
    it "redirects unauthenticated requests to admin pages to sign-in" do
      get "/admin/content"

      expect(response).to redirect_to(new_session_path)
    end

    it "allows access to admin pages after sign-in" do
      post session_path, params: { email_address: "user@example.com", password: "securepassword1" }
      get "/admin/content"

      expect(response).to have_http_status(:ok)
    end

    it "redirects back to the original URL after sign-in" do
      get "/admin/content/new"
      expect(response).to redirect_to(new_session_path)

      post session_path, params: { email_address: "user@example.com", password: "securepassword1" }
      expect(response).to redirect_to("http://www.example.com/admin/content/new")
    end
  end
end
