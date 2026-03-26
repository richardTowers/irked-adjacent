require "rails_helper"

RSpec.describe "Admin::FieldDefinitions", type: :request do
  let(:user) { create_and_sign_in_user }
  let(:team) { Team.create!(name: "Test Team") }
  let!(:content_type) { ContentType.create!(name: "Blog Post", team: team) }

  before do
    Membership.create!(user: user, team: team, role: "editor")
  end

  describe "POST /admin/content-types/:slug/fields" do
    context "with valid params" do
      it "creates a field definition and redirects to the show page" do
        expect {
          post "/admin/content-types/blog-post/fields", params: {
            field_definition: { name: "Title", api_key: "title", field_type: "string", position: 0 }
          }
        }.to change(FieldDefinition, :count).by(1)

        expect(response).to redirect_to(admin_content_type_path("blog-post"))
      end

      it "shows a success flash message after redirect" do
        post "/admin/content-types/blog-post/fields", params: {
          field_definition: { name: "Title", api_key: "title", field_type: "string", position: 0 }
        }

        follow_redirect!

        expect(response.body).to include("Field was successfully added.")
      end

      it "creates a required field when required is checked" do
        post "/admin/content-types/blog-post/fields", params: {
          field_definition: { name: "Title", api_key: "title", field_type: "string", position: 0, required: "1" }
        }

        expect(FieldDefinition.last.required).to be true
      end
    end

    context "with invalid params" do
      it "returns 422 and re-renders the show page with errors" do
        post "/admin/content-types/blog-post/fields", params: {
          field_definition: { name: "", api_key: "", field_type: "", position: 0 }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('role="alert"')
      end

      it "shows validation errors for invalid api_key" do
        post "/admin/content-types/blog-post/fields", params: {
          field_definition: { name: "Title", api_key: "Invalid Key!", field_type: "string", position: 0 }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("must start with a lowercase letter")
      end

      it "shows validation error for duplicate api_key" do
        content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)

        post "/admin/content-types/blog-post/fields", params: {
          field_definition: { name: "Another Title", api_key: "title", field_type: "string", position: 1 }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("already been taken")
      end
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "returns 404 for a content type belonging to another team" do
        post "/admin/content-types/other-type/fields", params: {
          field_definition: { name: "Title", api_key: "title", field_type: "string", position: 0 }
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /admin/content-types/:slug/fields/:id" do
    let!(:field) do
      content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
    end

    context "with valid params" do
      it "updates the field definition and redirects" do
        patch "/admin/content-types/blog-post/fields/#{field.id}", params: {
          field_definition: { name: "Updated Title" }
        }

        expect(response).to redirect_to(admin_content_type_path("blog-post"))
        expect(field.reload.name).to eq("Updated Title")
      end

      it "shows a success flash message after redirect" do
        patch "/admin/content-types/blog-post/fields/#{field.id}", params: {
          field_definition: { name: "Updated Title" }
        }

        follow_redirect!

        expect(response.body).to include("Field was successfully updated.")
      end

      it "updates the position" do
        patch "/admin/content-types/blog-post/fields/#{field.id}", params: {
          field_definition: { position: 5 }
        }

        expect(field.reload.position).to eq(5)
      end
    end

    context "with invalid params" do
      it "returns 422 and re-renders the show page with errors" do
        patch "/admin/content-types/blog-post/fields/#{field.id}", params: {
          field_definition: { name: "" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('role="alert"')
      end
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }
      let!(:other_field) do
        other_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
      end

      it "returns 404 for a field belonging to another team's content type" do
        patch "/admin/content-types/other-type/fields/#{other_field.id}", params: {
          field_definition: { name: "Hacked" }
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /admin/content-types/:slug/fields/:id" do
    let!(:field) do
      content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
    end

    it "deletes the field definition and redirects" do
      expect {
        delete "/admin/content-types/blog-post/fields/#{field.id}"
      }.to change(FieldDefinition, :count).by(-1)

      expect(response).to redirect_to(admin_content_type_path("blog-post"))
    end

    it "shows a success flash message after redirect" do
      delete "/admin/content-types/blog-post/fields/#{field.id}"

      follow_redirect!

      expect(response.body).to include("Field was successfully removed.")
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }
      let!(:other_field) do
        other_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
      end

      it "returns 404 for a field belonging to another team's content type" do
        expect {
          delete "/admin/content-types/other-type/fields/#{other_field.id}"
        }.not_to change(FieldDefinition, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "field remove button" do
    let!(:field) do
      content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
    end

    it "has a remove button with confirmation" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Remove")
      expect(response.body).to include("Existing node data for this field will become orphaned")
    end
  end

  describe "editor role authorization" do
    let(:member_user) { create_and_sign_in_user(email: "member@example.com") }
    let!(:field) { content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0) }

    before do
      Membership.create!(user: member_user, team: team, role: "member")
    end

    it "returns 403 when a member tries to create a field" do
      expect {
        post "/admin/content-types/blog-post/fields", params: { field_definition: { name: "Body", api_key: "body", field_type: "text" } }
      }.not_to change(FieldDefinition, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 when a member tries to update a field" do
      patch "/admin/content-types/blog-post/fields/#{field.id}", params: { field_definition: { name: "Updated" } }

      expect(response).to have_http_status(:forbidden)
      expect(field.reload.name).to eq("Title")
    end

    it "returns 403 when a member tries to delete a field" do
      expect {
        delete "/admin/content-types/blog-post/fields/#{field.id}"
      }.not_to change(FieldDefinition, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
