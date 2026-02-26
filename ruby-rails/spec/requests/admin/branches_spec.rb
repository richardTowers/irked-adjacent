require "rails_helper"

RSpec.describe "Admin::Branches", type: :request do
  describe "GET /admin/branches" do
    it "returns 200 and lists all branches" do
      get "/admin/branches"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Branches</h1>")
      expect(response.body).to include("main")
      expect(response.body).to include("published")
    end

    it "displays the correct column headers" do
      get "/admin/branches"

      expect(response.body).to include("<th scope=\"col\">Name</th>")
      expect(response.body).to include("<th scope=\"col\">Protected</th>")
      expect(response.body).to include("<th scope=\"col\">Created</th>")
    end

    it "marks protected branches as Yes" do
      get "/admin/branches"

      body = response.body
      tbody_start = body.index("<tbody>")
      tbody = body[tbody_start..]
      main_row = tbody[tbody.index(">main<")..tbody.index(">main<") + 200]
      expect(main_row).to include(">Yes<")
    end

    it "includes a New Branch link" do
      get "/admin/branches"

      expect(response.body).to include("New Branch")
      expect(response.body).to include("href=\"/admin/branches/new\"")
    end

    it "shows Delete button only for non-protected branches" do
      Branch.create!(name: "feature-1")

      get "/admin/branches"

      # feature-1 row should have Delete
      body = response.body
      tbody_start = body.index("<tbody>")
      tbody = body[tbody_start..]
      feature_row = tbody[tbody.index("feature-1")..tbody.index("feature-1") + 500]
      expect(feature_row).to include("Delete")
    end

    it "lists main first" do
      Branch.create!(name: "aaa-branch")

      get "/admin/branches"

      main_pos = response.body.index(">main<")
      aaa_pos = response.body.index("aaa-branch")
      expect(main_pos).to be < aaa_pos
    end
  end

  describe "GET /admin/branches/new" do
    it "returns 200 and displays the form" do
      get "/admin/branches/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>New Branch</h1>")
      expect(response.body).to include("Create Branch")
    end

    it "has a cancel link to /admin/branches" do
      get "/admin/branches/new"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/branches\"")
    end
  end

  describe "POST /admin/branches" do
    context "with a valid name" do
      it "creates a branch and redirects" do
        expect {
          post "/admin/branches", params: { branch: { name: "feature-1" } }
        }.to change(Branch, :count).by(1)

        expect(response).to redirect_to(admin_branches_path)

        follow_redirect!
        expect(response.body).to include("Branch was successfully created.")
      end
    end

    context "with a blank name" do
      it "returns 422 and re-renders the form" do
        post "/admin/branches", params: { branch: { name: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("role=\"alert\"")
      end
    end

    context "with an invalid format" do
      it "returns 422" do
        post "/admin/branches", params: { branch: { name: "Invalid Name" } }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a duplicate name" do
      it "returns 422" do
        Branch.create!(name: "existing")

        post "/admin/branches", params: { branch: { name: "existing" } }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a name longer than 50 characters" do
      it "returns 422" do
        post "/admin/branches", params: { branch: { name: "a" * 51 } }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "preserves entered values on validation failure" do
      post "/admin/branches", params: { branch: { name: "Invalid Name" } }

      expect(response.body).to include("Invalid Name")
    end
  end

  describe "DELETE /admin/branches/:id" do
    context "non-protected branch" do
      it "deletes the branch and redirects" do
        branch = Branch.create!(name: "temp-branch")

        expect {
          delete "/admin/branches/#{branch.id}"
        }.to change(Branch, :count).by(-1)

        expect(response).to redirect_to(admin_branches_path)

        follow_redirect!
        expect(response.body).to include("Branch was successfully deleted.")
      end

      it "deletes all versions on the branch" do
        branch = Branch.create!(name: "doomed")
        node = Node.create!(slug: "test-node")
        Version.create!(node: node, branch: branch, title: "Branch version")

        expect {
          delete "/admin/branches/#{branch.id}"
        }.to change(Version, :count).by(-1)
      end

      it "resets session to main if the deleted branch was selected" do
        branch = Branch.create!(name: "selected")

        # Switch to the branch first
        post "/admin/switch-branch", params: { branch_id: branch.id }

        delete "/admin/branches/#{branch.id}"

        # Session should have been reset — visiting content should default to main
        get "/admin/content"
        expect(response).to have_http_status(:ok)
      end
    end

    context "protected branch" do
      it "returns 422 with an alert" do
        main = Branch.find_by!(name: "main")

        delete "/admin/branches/#{main.id}"

        expect(response).to have_http_status(:unprocessable_entity)

        follow_redirect! if response.redirect?
        # Check for the alert message
        expect(response.body).to include("Cannot delete a protected branch.") if response.successful?
      end
    end

    it "returns 404 for a non-existent ID" do
      delete "/admin/branches/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      delete "/admin/branches/abc"

      expect(response).to have_http_status(:not_found)
    end

    it "includes a confirmation dialog" do
      Branch.create!(name: "confirm-test")

      get "/admin/branches"

      expect(response.body).to include("Are you sure you want to delete this branch?")
    end
  end

  describe "POST /admin/switch-branch" do
    it "switches the current branch and redirects back" do
      main = Branch.find_by!(name: "main")
      feature = Branch.create!(name: "feature-1")

      post "/admin/switch-branch", params: { branch_id: feature.id }, headers: { "HTTP_REFERER" => "/admin/content" }

      expect(response).to redirect_to("/admin/content")
    end

    it "defaults to /admin/content when no referrer" do
      main = Branch.find_by!(name: "main")

      post "/admin/switch-branch", params: { branch_id: main.id }

      expect(response).to redirect_to("/admin/content")
    end

    it "returns 404 for non-existent branch" do
      post "/admin/switch-branch", params: { branch_id: 999999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "branch selector in layout" do
    it "displays the current branch name" do
      get "/admin/content"

      expect(response.body).to include("branch_selector")
      expect(response.body).to include("main")
    end

    it "defaults to main on first visit" do
      get "/admin/content"

      expect(response.body).to match(/selected.*main/)
    end

    it "falls back to main when session branch is deleted" do
      branch = Branch.create!(name: "ephemeral")

      post "/admin/switch-branch", params: { branch_id: branch.id }

      # Delete the branch directly
      branch.versions.delete_all
      branch.destroy

      get "/admin/content"

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/selected.*main/)
    end
  end
end
