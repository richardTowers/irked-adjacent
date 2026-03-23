require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /registration/new" do
    it "returns 200 and renders the sign-up form" do
      get new_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign up")
      expect(response.body).to include("email_address")
      expect(response.body).to include("password")
      expect(response.body).to include("password_confirmation")
    end

    it "includes a link to sign in" do
      get new_registration_path

      expect(response.body).to include("Sign in")
    end
  end

  describe "POST /registration" do
    context "with valid params" do
      it "creates a user and redirects to root" do
        expect {
          post registration_path, params: {
            user: {
              email_address: "newuser@example.com",
              password: "securepassword1",
              password_confirmation: "securepassword1"
            }
          }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(root_url)
      end

      it "signs in the new user automatically" do
        post registration_path, params: {
          user: {
            email_address: "newuser@example.com",
            password: "securepassword1",
            password_confirmation: "securepassword1"
          }
        }

        expect(cookies[:session_id]).to be_present
      end

      it "shows a welcome flash message" do
        post registration_path, params: {
          user: {
            email_address: "newuser@example.com",
            password: "securepassword1",
            password_confirmation: "securepassword1"
          }
        }

        follow_redirect!
        # The root redirects to /admin/content, follow that too
        follow_redirect!
        expect(response.body).to include("Welcome! Your account has been created.")
      end
    end

    context "with mismatched passwords" do
      it "returns 422 and re-renders the form" do
        post registration_path, params: {
          user: {
            email_address: "newuser@example.com",
            password: "securepassword1",
            password_confirmation: "differentpassword"
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Sign up")
      end
    end

    context "with too-short password" do
      it "returns 422 and shows password length error" do
        post registration_path, params: {
          user: {
            email_address: "newuser@example.com",
            password: "short",
            password_confirmation: "short"
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("too short")
      end
    end

    context "with duplicate email" do
      before do
        User.create!(
          email_address: "taken@example.com",
          password: "securepassword1",
          password_confirmation: "securepassword1"
        )
      end

      it "returns 422 and shows uniqueness error" do
        post registration_path, params: {
          user: {
            email_address: "taken@example.com",
            password: "securepassword1",
            password_confirmation: "securepassword1"
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("already been taken")
      end
    end

    context "with blank email" do
      it "returns 422 and shows error" do
        post registration_path, params: {
          user: {
            email_address: "",
            password: "securepassword1",
            password_confirmation: "securepassword1"
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "when already authenticated" do
    before do
      user = User.create!(
        email_address: "existing@example.com",
        password: "securepassword1",
        password_confirmation: "securepassword1"
      )
      post session_path, params: { email_address: "existing@example.com", password: "securepassword1" }
    end

    it "redirects GET /registration/new to root" do
      get new_registration_path

      expect(response).to redirect_to(root_url)
    end

    it "redirects POST /registration to root" do
      post registration_path, params: {
        user: {
          email_address: "another@example.com",
          password: "securepassword1",
          password_confirmation: "securepassword1"
        }
      }

      expect(response).to redirect_to(root_url)
    end
  end
end
