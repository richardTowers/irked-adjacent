require "rails_helper"

RSpec.describe "Admin::ContentTypes", type: :request do
  let(:user) { create_and_sign_in_user }
  let(:team) { Team.create!(name: "Test Team") }

  before do
    Membership.create!(user: user, team: team, role: "editor")
  end

  describe "GET /admin/content-types" do
    context "when there are no content types" do
      it "returns 200 and shows the empty state" do
        get "/admin/content-types"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No content types yet.")
      end
    end

    context "when content types exist" do
      let!(:content_type) do
        ContentType.create!(name: "Blog Post", description: "A blog post", team: team)
      end

      before do
        content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0)
        content_type.field_definitions.create!(name: "Body", api_key: "body", field_type: "text", position: 1)
      end

      it "returns 200 and displays a table" do
        get "/admin/content-types"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<table>")
      end

      it "displays the correct column headers" do
        get "/admin/content-types"

        expect(response.body).to include('<th scope="col">Name</th>')
        expect(response.body).to include('<th scope="col">Team</th>')
        expect(response.body).to include('<th scope="col">Fields</th>')
        expect(response.body).to include('<th scope="col">Nodes</th>')
      end

      it "displays the content type name, team, and field count" do
        get "/admin/content-types"

        expect(response.body).to include("Blog Post")
        expect(response.body).to include("Test Team")
      end

      it "links each name to its show page" do
        get "/admin/content-types"

        expect(response.body).to include("href=\"/admin/content-types/blog-post\"")
      end
    end

    context "when user has no teams" do
      before do
        Membership.where(user: user).destroy_all
      end

      it "shows guidance to create or join a team" do
        get "/admin/content-types"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("You need to be a member of a team before you can create content types.")
      end
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:own_type) { ContentType.create!(name: "My Type", team: team) }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "only shows content types belonging to the user's teams" do
        get "/admin/content-types"

        expect(response.body).to include("My Type")
        expect(response.body).not_to include("Other Type")
      end
    end

    it "includes a 'New content type' link" do
      get "/admin/content-types"

      expect(response.body).to include("New content type")
      expect(response.body).to include("href=\"/admin/content-types/new\"")
    end

    it "sets the page title" do
      get "/admin/content-types"

      expect(response.body).to include("<title>Content Types</title>")
    end
  end

  describe "GET /admin/content-types/:slug" do
    let!(:content_type) do
      ContentType.create!(name: "Blog Post", description: "A blog post type", team: team)
    end

    it "returns 200 and shows the content type name" do
      get "/admin/content-types/blog-post"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Blog Post</h1>")
    end

    it "displays the content type details" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("blog-post")
      expect(response.body).to include("Test Team")
      expect(response.body).to include("A blog post type")
    end

    it "lists field definitions in position order" do
      content_type.field_definitions.create!(name: "Body", api_key: "body", field_type: "text", position: 1)
      content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", position: 0, required: true)

      get "/admin/content-types/blog-post"

      title_pos = response.body.index("title</code>")
      body_pos = response.body.index("body</code>")
      expect(title_pos).to be < body_pos
    end

    it "shows field details" do
      content_type.field_definitions.create!(name: "Title", api_key: "title", field_type: "string", required: true, position: 0)

      get "/admin/content-types/blog-post"

      expect(response.body).to include("Title")
      expect(response.body).to include("title</code>")
      expect(response.body).to include("string")
      expect(response.body).to include("Yes")
    end

    it "shows the empty fields state" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("No fields defined yet.")
    end

    it "includes an add field form" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Add Field")
      expect(response.body).to include("field_definition[name]")
      expect(response.body).to include("field_definition[api_key]")
      expect(response.body).to include("field_definition[field_type]")
    end

    it "includes edit and back links" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Edit")
      expect(response.body).to include("Back to content types")
    end

    it "includes a delete button" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Delete content type")
    end

    it "sets the page title" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("<title>Blog Post — Content Types</title>")
    end

    it "returns 404 for a non-existent slug" do
      get "/admin/content-types/nonexistent"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "returns 404 for a content type belonging to another team" do
        get "/admin/content-types/other-type"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /admin/content-types/new" do
    it "returns 200 and renders the form" do
      get "/admin/content-types/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>New Content Type</h1>")
    end

    it "has form fields for name, slug, description, and team" do
      get "/admin/content-types/new"

      expect(response.body).to include("content_type[name]")
      expect(response.body).to include("content_type[slug]")
      expect(response.body).to include("content_type[description]")
      expect(response.body).to include("content_type[team_id]")
    end

    it "has a team selector with the user's teams" do
      get "/admin/content-types/new"

      expect(response.body).to include("Test Team")
    end

    it "has a submit button labeled 'Create Content Type'" do
      get "/admin/content-types/new"

      expect(response.body).to include("Create Content Type")
    end

    it "has a cancel link" do
      get "/admin/content-types/new"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content-types\"")
    end

    it "sets the page title" do
      get "/admin/content-types/new"

      expect(response.body).to include("<title>New Content Type</title>")
    end

    context "when user has no teams" do
      before do
        Membership.where(user: user).destroy_all
      end

      it "returns 403 forbidden" do
        get "/admin/content-types/new"

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("Access Denied")
      end
    end
  end

  describe "POST /admin/content-types" do
    context "with valid params" do
      it "creates a content type and redirects to the show page" do
        expect {
          post "/admin/content-types", params: { content_type: { name: "Blog Post", team_id: team.id } }
        }.to change(ContentType, :count).by(1)

        content_type = ContentType.last
        expect(response).to redirect_to(admin_content_type_path(content_type.slug))
      end

      it "shows a success flash message after redirect" do
        post "/admin/content-types", params: { content_type: { name: "Blog Post", team_id: team.id } }

        follow_redirect!

        expect(response.body).to include("Content type was successfully created.")
      end

      it "has the flash message in an element with role='status'" do
        post "/admin/content-types", params: { content_type: { name: "Blog Post", team_id: team.id } }

        follow_redirect!

        expect(response.body).to include('role="status"')
      end

      it "auto-generates a slug from the name" do
        post "/admin/content-types", params: { content_type: { name: "Blog Post", team_id: team.id } }

        expect(ContentType.last.slug).to eq("blog-post")
      end
    end

    context "with a team the user does not belong to" do
      let(:other_team) { Team.create!(name: "Other Team") }

      it "returns 422 and does not create the content type" do
        expect {
          post "/admin/content-types", params: { content_type: { name: "Sneaky Type", team_id: other_team.id } }
        }.not_to change(ContentType, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with blank name" do
      it "returns 422 and re-renders the form with errors" do
        post "/admin/content-types", params: { content_type: { name: "", team_id: team.id } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("New Content Type")
        expect(response.body).to include('role="alert"')
      end

      it "marks the name field as aria-invalid" do
        post "/admin/content-types", params: { content_type: { name: "", team_id: team.id } }

        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("name-error")
      end
    end

    context "with duplicate slug" do
      before do
        ContentType.create!(name: "Blog Post", team: team)
      end

      it "returns 422 with error" do
        post "/admin/content-types", params: { content_type: { name: "Blog Post", slug: "blog-post", team_id: team.id } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end
  end

  describe "GET /admin/content-types/:slug/edit" do
    let!(:content_type) do
      ContentType.create!(name: "Blog Post", description: "A blog post", team: team)
    end

    it "returns 200 and displays the edit form" do
      get "/admin/content-types/blog-post/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Edit Content Type</h1>")
    end

    it "displays the team name" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).to include("Test Team")
    end

    it "does not include a team selector" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).not_to include("content_type[team_id]")
    end

    it "pre-fills the form with the content type's current values" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).to include("Blog Post")
      expect(response.body).to include("A blog post")
    end

    it "has a submit button labeled 'Update Content Type'" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).to include("Update Content Type")
    end

    it "has a cancel link to the show page" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content-types/blog-post\"")
    end

    it "sets the page title" do
      get "/admin/content-types/blog-post/edit"

      expect(response.body).to include("<title>Edit Blog Post — Content Types</title>")
    end

    it "returns 404 for a non-existent slug" do
      get "/admin/content-types/nonexistent/edit"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "returns 404 for a content type belonging to another team" do
        get "/admin/content-types/other-type/edit"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /admin/content-types/:slug" do
    let!(:content_type) do
      ContentType.create!(name: "Blog Post", description: "Original description", team: team)
    end

    context "with valid params" do
      it "updates the content type and redirects to the show page" do
        patch "/admin/content-types/blog-post", params: { content_type: { name: "Updated Post" } }

        content_type.reload
        expect(content_type.name).to eq("Updated Post")
        expect(response).to redirect_to(admin_content_type_path(content_type.slug))
      end

      it "shows a success flash message after redirect" do
        patch "/admin/content-types/blog-post", params: { content_type: { name: "Updated Post" } }

        follow_redirect!

        expect(response.body).to include("Content type was successfully updated.")
      end
    end

    context "with blank name" do
      it "returns 422 and re-renders the form with errors" do
        patch "/admin/content-types/blog-post", params: { content_type: { name: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Edit Content Type")
        expect(response.body).to include('role="alert"')
      end
    end

    it "returns 404 for a non-existent slug" do
      patch "/admin/content-types/nonexistent", params: { content_type: { name: "Nope" } }

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "returns 404 for a content type belonging to another team" do
        patch "/admin/content-types/other-type", params: { content_type: { name: "Hacked" } }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /admin/content-types/:slug" do
    let!(:content_type) do
      ContentType.create!(name: "Blog Post", team: team)
    end

    it "deletes the content type and redirects to the listing" do
      expect {
        delete "/admin/content-types/blog-post"
      }.to change(ContentType, :count).by(-1)

      expect(response).to redirect_to(admin_content_types_path)
    end

    it "shows a success flash message after redirect" do
      delete "/admin/content-types/blog-post"

      follow_redirect!

      expect(response.body).to include("Content type was successfully deleted.")
    end

    it "returns 404 for a non-existent slug" do
      delete "/admin/content-types/nonexistent"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let!(:other_type) { ContentType.create!(name: "Other Type", team: other_team) }

      it "returns 404 for a content type belonging to another team" do
        expect {
          delete "/admin/content-types/other-type"
        }.not_to change(ContentType, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "show page delete button" do
    let!(:content_type) { ContentType.create!(name: "Blog Post", team: team) }

    it "has a delete button rendered as a form with DELETE method" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Delete content type")
      expect(response.body).to include('name="_method"')
      expect(response.body).to include('value="delete"')
    end

    it "includes a confirmation dialog message" do
      get "/admin/content-types/blog-post"

      expect(response.body).to include("Are you sure you want to delete this content type?")
    end
  end

  describe "navigation" do
    it "includes a Content Types link in the nav" do
      get "/admin/content-types"

      expect(response.body).to include("Content Types")
      expect(response.body).to include("href=\"/admin/content-types\"")
    end
  end

  describe "editor role authorization" do
    let(:member_user) { create_and_sign_in_user(email: "member@example.com") }
    let!(:content_type) { ContentType.create!(name: "Blog Post", team: team) }

    before do
      Membership.create!(user: member_user, team: team, role: "member")
    end

    context "as a member" do
      it "can view the content types index" do
        get "/admin/content-types"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Blog Post")
      end

      it "can view a content type show page" do
        get "/admin/content-types/blog-post"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Blog Post")
      end

      it "does not see the New content type link on the index page" do
        get "/admin/content-types"

        expect(response.body).not_to include("New content type")
      end

      it "does not see the Edit link on the show page" do
        get "/admin/content-types/blog-post"

        expect(response.body).not_to include(">Edit</a>")
      end

      it "does not see the Delete button on the show page" do
        get "/admin/content-types/blog-post"

        expect(response.body).not_to include("Delete content type")
      end

      it "does not see the Add Field form on the show page" do
        get "/admin/content-types/blog-post"

        expect(response.body).not_to include("Add Field")
      end

      it "receives 403 when trying to access the new content type page" do
        get "/admin/content-types/new"

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("Access Denied")
      end

      it "receives 403 when trying to create a content type" do
        expect {
          post "/admin/content-types", params: { content_type: { name: "Sneaky", team_id: team.id } }
        }.not_to change(ContentType, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it "receives 403 when trying to edit a content type" do
        get "/admin/content-types/blog-post/edit"

        expect(response).to have_http_status(:forbidden)
      end

      it "receives 403 when trying to update a content type" do
        patch "/admin/content-types/blog-post", params: { content_type: { name: "Updated" } }

        expect(response).to have_http_status(:forbidden)
        expect(content_type.reload.name).to eq("Blog Post")
      end

      it "receives 403 when trying to delete a content type" do
        delete "/admin/content-types/blog-post"

        expect(response).to have_http_status(:forbidden)
        expect(ContentType.exists?(content_type.id)).to be true
      end
    end

    context "with editor role in a different team" do
      let(:other_team) { Team.create!(name: "Other Team") }

      before do
        Membership.create!(user: member_user, team: other_team, role: "editor")
      end

      it "receives 403 when trying to edit a content type in the non-editor team" do
        get "/admin/content-types/blog-post/edit"

        expect(response).to have_http_status(:forbidden)
      end

      it "receives 403 when trying to delete a content type in the non-editor team" do
        delete "/admin/content-types/blog-post"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
