require "rails_helper"

RSpec.describe "Admin::Content", type: :request do
  let(:user) { create_and_sign_in_user }
  let(:team) { Team.create!(name: "Test Team") }
  let(:content_type) { ContentType.create!(name: "Page", team: team) }

  before do
    Membership.create!(user: user, team: team)
  end

  describe "GET /admin/content" do
    context "when there are no nodes" do
      it "returns 200 and shows the empty state" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No content yet.")
      end
    end

    context "when nodes exist" do
      let!(:older_node) do
        Node.create!(title: "Older Post", published: true, team: team, content_type: content_type)
      end

      let!(:newer_node) do
        Node.create!(title: "Newer Post", published: false, team: team, content_type: content_type)
      end

      it "returns 200 and displays a table" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<table>")
      end

      it "displays the correct column headers" do
        get "/admin/content"

        expect(response.body).to include("<th scope=\"col\">Title</th>")
        expect(response.body).to include("<th scope=\"col\">Slug</th>")
        expect(response.body).to include("<th scope=\"col\">Team</th>")
        expect(response.body).to include("<th scope=\"col\">Status</th>")
        expect(response.body).to include("<th scope=\"col\">Updated</th>")
      end

      it "displays the team name in the table" do
        get "/admin/content"

        expect(response.body).to include("Test Team")
      end

      it "orders nodes by updated_at descending" do
        get "/admin/content"

        newer_pos = response.body.index("Newer Post")
        older_pos = response.body.index("Older Post")
        expect(newer_pos).to be < older_pos
      end

      it "links each title to its show page" do
        get "/admin/content"

        expect(response.body).to include("href=\"/admin/content/#{newer_node.id}\"")
        expect(response.body).to include("href=\"/admin/content/#{older_node.id}\"")
      end

      it "displays the correct status text" do
        get "/admin/content"

        expect(response.body).to include("Published")
        expect(response.body).to include("Draft")
      end
    end

    context "when user has no teams" do
      before do
        Membership.where(user: user).destroy_all
      end

      it "shows guidance to create or join a team" do
        get "/admin/content"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("You need to be a member of a team before you can create content.")
        expect(response.body).to include("Create a team")
      end
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }
      let!(:own_node) { Node.create!(title: "My Node", team: team, content_type: content_type) }
      let!(:other_node) { Node.create!(title: "Other Node", team: other_team, content_type: other_ct) }
      let!(:unassigned_node) { Node.create!(title: "Unassigned Node", team: other_team, content_type: other_ct) }

      it "only shows nodes belonging to the user's teams" do
        get "/admin/content"

        expect(response.body).to include("My Node")
        expect(response.body).not_to include("Other Node")
      end
    end

    it "includes a 'New Node' link pointing to /admin/content/new" do
      get "/admin/content"

      expect(response.body).to include("New Node")
      expect(response.body).to include("href=\"/admin/content/new\"")
    end
  end

  describe "GET /admin/content/:id" do
    let!(:body_field) do
      content_type.field_definitions.create!(name: "Body", api_key: "body", field_type: "text", position: 0)
    end

    let!(:node) do
      body_field # ensure field definition exists before node creation
      Node.create!(
        title: "Test Node",
        fields: { "body" => "Some <strong>bold</strong> content" },
        published: true,
        team: team,
        content_type: content_type
      )
    end

    it "returns 200 and shows the node title" do
      get "/admin/content/#{node.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Test Node</h1>")
    end

    it "displays the node details" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("test-node")
      expect(response.body).to include("Published")
    end

    it "displays the team name" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Test Team")
    end

    it "displays the content type name" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Page")
    end

    it "escapes HTML in the fields" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("&lt;strong&gt;bold&lt;/strong&gt;")
      expect(response.body).not_to include("<strong>bold</strong>")
    end

    it "includes a 'Back to content' link to /admin/content" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Back to content")
      expect(response.body).to include("href=\"/admin/content\"")
    end

    it "includes an 'Edit' link to the edit page" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Edit")
      expect(response.body).to include("href=\"/admin/content/#{node.id}/edit\"")
    end

    it "returns 404 for a non-existent ID" do
      get "/admin/content/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      get "/admin/content/abc"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }
      let!(:other_node) { Node.create!(title: "Other Node", team: other_team, content_type: other_ct) }

      it "returns 404 for a node belonging to another team" do
        get "/admin/content/#{other_node.id}"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /admin/content/new" do
    it "returns 200 and renders the form" do
      get "/admin/content/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>New Node</h1>")
    end

    it "has form fields for title, slug, content_type, and published" do
      get "/admin/content/new"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[slug]")
      expect(response.body).to include("node[content_type_id]")
      expect(response.body).to include("node[published]")
    end

    it "has a team selector dropdown" do
      get "/admin/content/new"

      expect(response.body).to include("node[team_id]")
      expect(response.body).to include("Test Team")
    end

    it "has a label for the team selector" do
      get "/admin/content/new"

      expect(response.body).to match(/<label for="node_team_id">Team<\/label>/)
    end

    it "has a submit button labeled 'Create Node'" do
      get "/admin/content/new"

      expect(response.body).to include("Create Node")
    end

    it "has a cancel link to /admin/content" do
      get "/admin/content/new"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content\"")
    end

    it "marks the title field as required" do
      get "/admin/content/new"

      expect(response.body).to match(/required="required"[^>]*name="node\[title\]"/)
    end

    context "when user has no teams" do
      before do
        Membership.where(user: user).destroy_all
      end

      it "shows a message instead of the form" do
        get "/admin/content/new"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("You need to be a member of a team before you can create content.")
        expect(response.body).not_to include("node[title]")
      end
    end
  end

  describe "POST /admin/content" do
    context "with valid params" do
      it "creates a node and redirects to the show page" do
        expect {
          post "/admin/content", params: { node: { title: "My First Post", team_id: team.id, content_type_id: content_type.id } }
        }.to change(Node, :count).by(1)

        node = Node.last
        expect(response).to redirect_to(admin_content_path(node))
      end

      it "shows a success flash message after redirect" do
        post "/admin/content", params: { node: { title: "My First Post", team_id: team.id, content_type_id: content_type.id } }

        follow_redirect!

        expect(response.body).to include("Node was successfully created.")
      end

      it "has the flash message in an element with role='status'" do
        post "/admin/content", params: { node: { title: "Flash Test", team_id: team.id, content_type_id: content_type.id } }

        follow_redirect!

        expect(response.body).to include('role="status"')
        expect(response.body).to include("Node was successfully created.")
      end
    end

    context "with a team the user does not belong to" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }

      it "returns 422 and does not create the node" do
        expect {
          post "/admin/content", params: { node: { title: "Sneaky Post", team_id: other_team.id, content_type_id: other_ct.id } }
        }.not_to change(Node, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with blank title" do
      it "returns 422 and re-renders the form with errors" do
        post "/admin/content", params: { node: { title: "", team_id: team.id, content_type_id: content_type.id } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("New Node")
        expect(response.body).to include("role=\"alert\"")
      end

      it "marks the title field as aria-invalid" do
        post "/admin/content", params: { node: { title: "", team_id: team.id, content_type_id: content_type.id } }

        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("title-error")
      end
    end

    context "slug handling" do
      it "auto-generates a slug from the title when slug is blank" do
        post "/admin/content", params: { node: { title: "My Great Post", team_id: team.id, content_type_id: content_type.id } }

        node = Node.last
        expect(node.slug).to eq("my-great-post")
      end

      it "uses the provided slug when one is given" do
        post "/admin/content", params: { node: { title: "My Great Post", slug: "custom-slug", team_id: team.id, content_type_id: content_type.id } }

        node = Node.last
        expect(node.slug).to eq("custom-slug")
      end

      it "returns 422 with error when slug is a duplicate" do
        Node.create!(title: "Existing", slug: "taken-slug", team: team, content_type: content_type)

        post "/admin/content", params: { node: { title: "New Post", slug: "taken-slug", team_id: team.id, content_type_id: content_type.id } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end

    context "published flag" do
      it "sets published to true and records published_at when checked" do
        post "/admin/content", params: { node: { title: "Published Post", published: "1", team_id: team.id, content_type_id: content_type.id } }

        node = Node.last
        expect(node.published).to be true
        expect(node.published_at).not_to be_nil
      end

      it "defaults to draft when published is not checked" do
        post "/admin/content", params: { node: { title: "Draft Post", team_id: team.id, content_type_id: content_type.id } }

        node = Node.last
        expect(node.published).to be false
        expect(node.published_at).to be_nil
      end
    end

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        post "/admin/content", params: { node: { title: "Safe Post", created_at: "2000-01-01", team_id: team.id, content_type_id: content_type.id } }

        node = Node.last
        expect(node.title).to eq("Safe Post")
        expect(node.created_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end
  end

  describe "GET /admin/content/:id/edit" do
    let!(:node) do
      Node.create!(title: "Editable Node", slug: "editable-node", published: false, team: team, content_type: content_type)
    end

    it "returns 200 and displays the edit form" do
      get "/admin/content/#{node.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>Edit Node</h1>")
    end

    it "displays the team name" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Test Team")
    end

    it "does not include a team selector" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).not_to include("node[team_id]")
    end

    it "pre-fills the form with the node's current values" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Editable Node")
      expect(response.body).to include("editable-node")
    end

    it "has form fields for title, slug, and published" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("node[title]")
      expect(response.body).to include("node[slug]")
      expect(response.body).to include("node[published]")
    end

    it "displays the content type name as read-only" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Page")
      expect(response.body).not_to include("node[content_type_id]")
    end

    it "has a submit button labeled 'Update Node'" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Update Node")
    end

    it "has a cancel link to the node's show page" do
      get "/admin/content/#{node.id}/edit"

      expect(response.body).to include("Cancel")
      expect(response.body).to include("href=\"/admin/content/#{node.id}\"")
    end

    it "returns 404 for a non-existent ID" do
      get "/admin/content/999999/edit"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }
      let!(:other_node) { Node.create!(title: "Other Node", team: other_team, content_type: other_ct) }

      it "returns 404 for a node belonging to another team" do
        get "/admin/content/#{other_node.id}/edit"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /admin/content/:id" do
    let!(:node) do
      Node.create!(title: "Original Title", slug: "original-title", published: false, team: team, content_type: content_type)
    end

    context "with valid params" do
      it "updates the node and redirects to the show page" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        expect(response).to redirect_to(admin_content_path(node))
        expect(node.reload.title).to eq("Updated Title")
      end

      it "shows a success flash message after redirect" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include("Node was successfully updated.")
      end

      it "has the flash message in an element with role='status'" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Updated Title" } }

        follow_redirect!

        expect(response.body).to include('role="status"')
        expect(response.body).to include("Node was successfully updated.")
      end
    end

    context "with blank title" do
      it "returns 422 and re-renders the form with errors" do
        patch "/admin/content/#{node.id}", params: { node: { title: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Edit Node")
        expect(response.body).to include("role=\"alert\"")
      end

      it "marks the title field as aria-invalid" do
        patch "/admin/content/#{node.id}", params: { node: { title: "" } }

        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("title-error")
      end
    end

    context "slug handling" do
      it "returns 422 with error when slug duplicates another node" do
        Node.create!(title: "Other Node", slug: "taken-slug", team: team, content_type: content_type)

        patch "/admin/content/#{node.id}", params: { node: { slug: "taken-slug" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("slug-error")
      end
    end

    context "published flag" do
      it "sets published_at when transitioning from false to true" do
        patch "/admin/content/#{node.id}", params: { node: { published: "1" } }

        node.reload
        expect(node.published).to be true
        expect(node.published_at).not_to be_nil
      end

      it "preserves published_at when unchecking published" do
        node.update!(published: true)
        original_published_at = node.reload.published_at

        patch "/admin/content/#{node.id}", params: { node: { published: "0" } }

        node.reload
        expect(node.published).to be false
        expect(node.published_at).to eq(original_published_at)
      end
    end

    context "strong parameters" do
      it "ignores unpermitted parameters" do
        patch "/admin/content/#{node.id}", params: { node: { title: "Safe Update", created_at: "2000-01-01" } }

        node.reload
        expect(node.title).to eq("Safe Update")
        expect(node.created_at).not_to eq(Time.zone.parse("2000-01-01"))
      end
    end

    it "returns 404 for a non-existent ID" do
      patch "/admin/content/999999", params: { node: { title: "Nope" } }

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }
      let!(:other_node) { Node.create!(title: "Other Node", team: other_team, content_type: other_ct) }

      it "returns 404 for a node belonging to another team" do
        patch "/admin/content/#{other_node.id}", params: { node: { title: "Hacked" } }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /admin/content/:id" do
    let!(:node) do
      Node.create!(title: "Doomed Node", slug: "doomed-node", team: team, content_type: content_type)
    end

    it "deletes the node and redirects to the listing page" do
      expect {
        delete "/admin/content/#{node.id}"
      }.to change(Node, :count).by(-1)

      expect(response).to redirect_to(admin_content_index_path)
    end

    it "shows a success flash message after redirect" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).to include("Node was successfully deleted.")
    end

    it "has the flash message in an element with role='status'" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).to include('role="status"')
      expect(response.body).to include("Node was successfully deleted.")
    end

    it "removes the node from the listing" do
      delete "/admin/content/#{node.id}"

      follow_redirect!

      expect(response.body).not_to include("Doomed Node")
    end

    it "returns 404 for a non-existent ID" do
      delete "/admin/content/999999"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-integer ID" do
      delete "/admin/content/abc"

      expect(response).to have_http_status(:not_found)
    end

    context "authorization" do
      let(:other_team) { Team.create!(name: "Other Team") }
      let(:other_ct) { ContentType.create!(name: "Other Page", team: other_team) }
      let!(:other_node) { Node.create!(title: "Other Node", team: other_team, content_type: other_ct) }

      it "returns 404 for a node belonging to another team" do
        expect {
          delete "/admin/content/#{other_node.id}"
        }.not_to change(Node, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "dynamic node forms" do
    let(:event_type) do
      ContentType.create!(name: "Event", team: team)
    end

    let!(:string_field) do
      event_type.field_definitions.create!(
        name: "Venue", api_key: "venue", field_type: "string", required: true, position: 0
      )
    end

    let!(:text_field) do
      event_type.field_definitions.create!(
        name: "Description", api_key: "description", field_type: "text", required: false, position: 1
      )
    end

    let!(:integer_field) do
      event_type.field_definitions.create!(
        name: "Capacity", api_key: "capacity", field_type: "integer", required: false, position: 2
      )
    end

    let!(:decimal_field) do
      event_type.field_definitions.create!(
        name: "Price", api_key: "price", field_type: "decimal", required: false, position: 3
      )
    end

    let!(:boolean_field) do
      event_type.field_definitions.create!(
        name: "Featured", api_key: "is_featured", field_type: "boolean", required: false, position: 4
      )
    end

    let!(:date_field) do
      event_type.field_definitions.create!(
        name: "Event Date", api_key: "event_date", field_type: "date", required: true, position: 5
      )
    end

    let!(:datetime_field) do
      event_type.field_definitions.create!(
        name: "Registration Deadline", api_key: "registration_deadline", field_type: "datetime", required: false, position: 6
      )
    end

    describe "GET /admin/content/new with content_type_id" do
      it "shows a content type selector" do
        get "/admin/content/new"

        expect(response.body).to include("Content type")
        expect(response.body).to include("content_type_id")
      end

      it "renders fields for the selected content type" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("node[fields][venue]")
        expect(response.body).to include("node[fields][description]")
        expect(response.body).to include("node[fields][capacity]")
        expect(response.body).to include("node[fields][price]")
        expect(response.body).to include("node[fields][is_featured]")
        expect(response.body).to include("node[fields][event_date]")
        expect(response.body).to include("node[fields][registration_deadline]")
      end

      it "renders the correct input types" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        # String field -> text input
        expect(response.body).to match(/type="text"[^>]*name="node\[fields\]\[venue\]"/)
        # Integer field -> number input with step=1
        expect(response.body).to match(/type="number"[^>]*name="node\[fields\]\[capacity\]"[^>]*step="1"/)
        # Decimal field -> number input with step=any
        expect(response.body).to match(/type="number"[^>]*name="node\[fields\]\[price\]"[^>]*step="any"/)
        # Boolean field -> checkbox
        expect(response.body).to match(/type="checkbox"[^>]*name="node\[fields\]\[is_featured\]"/)
        # Date field -> date input
        expect(response.body).to match(/type="date"[^>]*name="node\[fields\]\[event_date\]"/)
        # Datetime field -> datetime-local input
        expect(response.body).to match(/type="datetime-local"[^>]*name="node\[fields\]\[registration_deadline\]"/)
      end

      it "renders text fields as textareas" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        expect(response.body).to match(/<textarea[^>]*name="node\[fields\]\[description\]"/)
      end

      it "marks required fields with aria-required and visual indicator" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        # Attributes may appear in any order
        expect(response.body).to include('aria-required="true"')
        expect(response.body).to include('name="node[fields][venue]"')
        expect(response.body).to include('<abbr title="required">*</abbr>')
      end

      it "renders fields in position order" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        venue_pos = response.body.index("node[fields][venue]")
        description_pos = response.body.index("node[fields][description]")
        capacity_pos = response.body.index("node[fields][capacity]")
        expect(venue_pos).to be < description_pos
        expect(description_pos).to be < capacity_pos
      end

      it "renders universal fields above content-type fields" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        title_pos = response.body.index("node[title]")
        venue_pos = response.body.index("node[fields][venue]")
        expect(title_pos).to be < venue_pos
      end

      it "wraps dynamic fields in a fieldset with legend" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        expect(response.body).to include("<fieldset>")
        expect(response.body).to include("<legend>Fields</legend>")
      end

      it "has labels with for attributes matching input ids" do
        get "/admin/content/new", params: { content_type_id: event_type.id }

        expect(response.body).to include('for="node_fields_venue"')
        expect(response.body).to include('id="node_fields_venue"')
      end

      it "pre-selects the content type when the team has only one" do
        # Remove the default "Page" content type, keep only event_type
        content_type.destroy!
        get "/admin/content/new"

        expect(response.body).to include("node[fields][venue]")
      end

      it "does not render fields when no content type is selected and multiple types exist" do
        # With multiple content types, none is auto-selected
        content_type # ensure the "Page" type also exists
        get "/admin/content/new"

        expect(response.body).not_to include("node[fields]")
        expect(response.body).not_to include("<fieldset>")
      end
    end

    describe "POST /admin/content with dynamic fields" do
      it "creates a node with field values" do
        expect {
          post "/admin/content", params: {
            node: {
              title: "Tech Conference",
              team_id: team.id,
              content_type_id: event_type.id,
              fields: {
                venue: "Convention Center",
                description: "A great event",
                capacity: "500",
                price: "29.99",
                is_featured: "true",
                event_date: "2026-06-15",
                registration_deadline: "2026-06-01T09:00:00"
              }
            }
          }
        }.to change(Node, :count).by(1)

        node = Node.last
        expect(node.fields["venue"]).to eq("Convention Center")
        expect(node.fields["capacity"]).to eq(500)
        expect(node.fields["price"]).to eq(29.99)
        expect(node.fields["is_featured"]).to eq(true)
        expect(node.fields["event_date"]).to eq("2026-06-15")
      end

      it "defaults boolean fields to false when unchecked" do
        post "/admin/content", params: {
          node: {
            title: "Simple Event",
            team_id: team.id,
            content_type_id: event_type.id,
            fields: {
              venue: "Park",
              is_featured: "false",
              event_date: "2026-07-01"
            }
          }
        }

        node = Node.last
        expect(node.fields["is_featured"]).to eq(false)
      end

      it "casts integer and decimal fields from string params" do
        post "/admin/content", params: {
          node: {
            title: "Typed Event",
            team_id: team.id,
            content_type_id: event_type.id,
            fields: {
              venue: "Hall",
              capacity: "100",
              price: "9.50",
              event_date: "2026-08-01"
            }
          }
        }

        node = Node.last
        expect(node.fields["capacity"]).to be_an(Integer)
        expect(node.fields["price"]).to be_a(Float)
      end

      it "rejects unknown field keys" do
        post "/admin/content", params: {
          node: {
            title: "Sneaky Event",
            team_id: team.id,
            content_type_id: event_type.id,
            fields: {
              venue: "Hall",
              event_date: "2026-09-01",
              hacked_field: "gotcha"
            }
          }
        }

        # The unknown key should be stripped by strong params
        expect(Node.last).to be_present
        expect(Node.last.fields).not_to have_key("hacked_field")
      end

      it "shows validation errors next to the correct fields" do
        post "/admin/content", params: {
          node: {
            title: "Bad Event",
            team_id: team.id,
            content_type_id: event_type.id,
            fields: {
              venue: "",
              event_date: ""
            }
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('aria-invalid="true"')
        expect(response.body).to include("fields-venue-error")
        expect(response.body).to include("aria-describedby")
      end
    end

    describe "GET /admin/content/:id/edit with dynamic fields" do
      let!(:event_node) do
        Node.create!(
          title: "Existing Event",
          team: team,
          content_type: event_type,
          fields: {
            "venue" => "Old Venue",
            "description" => "Old description",
            "capacity" => 200,
            "price" => 15.50,
            "is_featured" => true,
            "event_date" => "2026-05-01"
          }
        )
      end

      it "renders fields with current values" do
        get "/admin/content/#{event_node.id}/edit"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Old Venue")
        expect(response.body).to include("Old description")
        expect(response.body).to include("200")
        expect(response.body).to include("15.5")
        expect(response.body).to include("2026-05-01")
      end

      it "checks the boolean checkbox when the value is true" do
        get "/admin/content/#{event_node.id}/edit"

        # Checkbox with checked attribute and correct name (attributes may be in any order)
        expect(response.body).to include('checked="checked"')
        expect(response.body).to include('name="node[fields][is_featured]"')
      end

      it "shows content type name as read-only" do
        get "/admin/content/#{event_node.id}/edit"

        expect(response.body).to include("Event")
        expect(response.body).not_to include('name="node[content_type_id]"')
      end
    end

    describe "PATCH /admin/content/:id with dynamic fields" do
      let!(:event_node) do
        Node.create!(
          title: "Existing Event",
          team: team,
          content_type: event_type,
          fields: {
            "venue" => "Old Venue",
            "is_featured" => true,
            "event_date" => "2026-05-01"
          }
        )
      end

      it "updates field values" do
        patch "/admin/content/#{event_node.id}", params: {
          node: {
            fields: {
              venue: "New Venue",
              is_featured: "false",
              event_date: "2026-06-01"
            }
          }
        }

        expect(response).to redirect_to(admin_content_path(event_node))
        event_node.reload
        expect(event_node.fields["venue"]).to eq("New Venue")
        expect(event_node.fields["is_featured"]).to eq(false)
        expect(event_node.fields["event_date"]).to eq("2026-06-01")
      end

      it "shows validation errors on update" do
        patch "/admin/content/#{event_node.id}", params: {
          node: {
            fields: {
              venue: "",
              event_date: ""
            }
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("fields-venue-error")
      end
    end

    describe "reference fields" do
      let(:article_type) { ContentType.create!(name: "Article", team: team) }
      let!(:article_ref_field) do
        article_type.field_definitions.create!(
          name: "Related Article", api_key: "related_article", field_type: "reference",
          required: false, position: 0,
          validations: { "allowed_content_types" => [article_type.id] }
        )
      end

      let!(:article_node) do
        Node.create!(title: "First Article", team: team, content_type: article_type)
      end

      let!(:event_node) do
        Node.create!(title: "Some Event", team: team, content_type: event_type,
          fields: { "venue" => "Hall", "event_date" => "2026-01-01" })
      end

      it "shows eligible nodes in the reference dropdown" do
        get "/admin/content/new", params: { content_type_id: article_type.id }

        expect(response.body).to include("First Article (Article)")
      end

      it "filters by allowed_content_types" do
        get "/admin/content/new", params: { content_type_id: article_type.id }

        # The event node should not appear since allowed_content_types only includes article_type
        expect(response.body).not_to include("Some Event (Event)")
      end

      it "renders reference field as a select" do
        get "/admin/content/new", params: { content_type_id: article_type.id }

        expect(response.body).to match(/<select[^>]*name="node\[fields\]\[related_article\]"/)
      end
    end
  end

  describe "show page delete button" do
    let!(:node) { Node.create!(title: "Test Node", team: team, content_type: content_type) }

    it "has a delete button rendered as a form with DELETE method" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Delete Node")
      expect(response.body).to include('name="_method"')
      expect(response.body).to include('value="delete"')
    end

    it "includes a confirmation dialog message" do
      get "/admin/content/#{node.id}"

      expect(response.body).to include("Are you sure you want to delete this node? This action cannot be undone.")
    end
  end
end
